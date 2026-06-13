# Pipeline jobs — the architecture

**What this is.** The companion [coreutil-lib-interface.md](coreutil-lib-interface.md) gives the *thesis*: capabilities compose as pipeline jobs, OS-based not framework-based, each coreutil usable as a CLI and as a library block. It stops at the thesis. This document gives the *architecture* — the concrete interfaces a pipeline job is built from, and why we invent none of them.

The thesis names two primitives: **command** (the node) and **pipe** (the connector). The keystone of this document is that both already exist, in `dart:io`, and need no reinvention:

- the command is a **`Process`** — `stdin`, `stdout`, `stderr`, `exitCode`. Nothing more is a command than that.
- the pipe is a **`Pipe`** (or, in the common case, a `Stream`/`IOSink` pair) — a unidirectional byte channel.

"Command" was the wrong name because it implied something to design. The right name is `Process`, and Dart hands it to us as an *interface* — an abstract class you may `implements`. That single fact is the whole architecture.

---

## 1. The primitives are `dart:io`'s

```dart
abstract interface class Process {
  IOSink            get stdin;   // write end of this node's input
  Stream<List<int>> get stdout;  // read end of its output
  Stream<List<int>> get stderr;  // out-of-band
  Future<int>       get exitCode;
  // pid, kill() — process control
}
```

A real binary is reached through `Process.start(exe, args)`. But because `Process` is an *interface*, a coreutil written in Dart can **`implements Process`** and be, for every composition purpose, indistinguishable from a forked binary — its `stdout` fed by in-isolate computation rather than an OS pipe. Verified: `class C implements Process` analyzes clean.

The connector is equally given. `Pipe.create()` returns a `.read` (`Stream<List<int>>`) and a `.write` (`IOSink`) — a byte channel with backpressure. In the common in-language case you do not even need it: wiring one node's `stdout` straight into the next node's `stdin` *is* the pipe.

We invent nothing. The userland's composition layer is `dart:io`'s process model, used as intended.

---

## 2. The shell is the wiring

A Unix shell, stripped to its essence, does one thing with a pipeline: start the processes and connect their stdio. In Dart that is a few lines:

```dart
// foo.sh:  cat foo.txt | sort | cut -f1 | wc -l
final cat  = await Process.start('cat',  ['foo.txt']);
final sort = await Process.start('sort', []);
final cut  = await Process.start('cut',  ['-f1']);
final wc   = await Process.start('wc',   ['-l']);

cat.stdout.pipe(sort.stdin);          // |
sort.stdout.pipe(cut.stdin);          // |
cut.stdout.pipe(wc.stdin);            // |
await stdout.addStream(wc.stdout);    // > terminal — the real stdout, never closed
```

The translation `foo.sh → foo.dart` is **mechanical**: each `|` is one `Stream.pipe` — which transfers the bytes *and* closes the downstream `stdin` at EOF, so each stage terminates in turn. (`addStream` alone would transfer bytes but leave the downstream open, hanging the pipeline on a `stdin` that never sees EOF — the one trap; `pipe` does the close. Only the final write to the real `stdout` uses `addStream`, because that sink must stay open.) There is no graph engine, no runtime, no inversion of control — the script owns the sequence, exactly as the shell script did. This is the thesis made literal: *the program you write with the primitives is the workflow.*

---

## 3. coreutil-as-lib, and fusion as a swapped constructor

Now replace one real binary with a Dart coreutil that `implements Process`:

```dart
final sort = SortProcess(['-n']);        // not Process.start('sort', …)
sort.stdout.pipe(cut.stdin);               // the wiring does not change
```

This is the entire mechanism behind "the fused pipeline mirrors the shell pipeline line for line." The wiring code is **identical** whether each node is `Process.start('sort')` (a forked binary) or `SortProcess([…])` (an in-isolate fake). Only the *constructor* differs. Fusion is not a rewrite of the pipeline — it is the choice of which `Process` each stage is built from:

| every node is… | result |
|---|---|
| `Process.start(…)` | N OS processes, kernel-wired — the shell's behavior |
| a fake `implements Process` | one isolate, cooperatively scheduled — fusion |
| a mix | hot stages fused, the rest forked — fusion at the seams you choose |

The acceptance test passes **by construction**, because both forms target the same `Process` interface. And the `bin/` entrypoint of every coreutil falls out for free: a trivial `main()` that constructs the fake `Process` and pumps it against the real `stdin`/`stdout`.

> The CLI form and the library form are the same class at two fusion levels. The executable is the fake `Process` talking to OS stdio; the library is the fake `Process` talking to the next stage's `stdin`. One implementation, two wirings.

---

## 4. The five shapes are channel-touch patterns

[The thesis, §3](coreutil-lib-interface.md) lists five command shapes. They are not five types — they are *one* type (`Process`) touching different channels:

| shape | which channels it touches | example |
|---|---|---|
| **source** | ignores `stdin`; writes `stdout` | `ls`, `cat file` |
| **filter** | reads `stdin`; writes `stdout` | `sort`, `cut` |
| **sink** | reads `stdin`; writes nothing | a writer-to-disk |
| **reducer** | reads all `stdin`; writes one value at EOF | `wc`, `sort` |
| **fan-out** | reads `stdin`; writes `stdout` **+ injected sinks** | `tee` |

No shape needs a distinct interface — this is the lesson paid for once already, when modelling the node as `StreamTransformer<I,O>` forced source, sink, reducer, and `tee` to arrive as special cases. `StreamTransformer` *is* the filter shape: one of five, mistaken for the whole. `Process` has no such bias; a source is simply a `Process` that never reads `stdin`.

**Fan-out and the side channels.** `tee` is the one shape that branches the line into a graph, and `Process` has only one `stdout`. The branch is expressed not by inventing extra fds but by *constructor injection*: a `TeeProcess` is handed the additional `IOSink`s it should duplicate into.

```dart
TeeProcess(List<IOSink> branches);   // stdin → stdout AND each branch
```

The side channels are ordinary sinks the node was given — the next stage's `stdin`, a file, another fused pipeline. Fan-out stays a `Process`; the graph lives in how its branches were wired, not in a richer node type.

---

## 5. Two composition registers

`Process.stdout` is `Stream<List<int>>` — **bytes**. This is the honest base contract, and it has a consequence the thesis overstated: across a byte boundary, each stage still encodes and decodes. Fusing the processes does **not** by itself make per-stage serialization disappear.

It does not need to. The cost of these pipelines is I/O wait — a device answering — not CPU spent on codecs; a chat turn pays in latency, not parsing. So the real wins of fusion are elsewhere and remain: **one process** (deployment, startup, zero IPC setup), **deterministic ordering**, **no kernel buffer**, and asynchrony confined to the true I/O boundary while the transforming middle runs promptly and in order.

That gives two registers, and the architecture keeps them distinct:

1. **Process composition — the spine.** Byte streams over the `Process` interface; real or fake nodes wired identically; serialization present and cheap. This is what a shell does, what the POC proves, and what every heterogeneous pipeline uses. Faithful, direct, and the default.

2. **Typed fusion — an opt-in optimization.** When two adjacent fused stages share a value type, the fake `Process` may expose a typed port that hands the live value across without the byte round-trip — *here* serialization disappears. It is a richer contract between cooperating stages, never the base primitive, and never required to compose.

The mistake to avoid is making register 2 the foundation — typing the pipe end to end and rediscovering the `StreamTransformer` trap one layer up. The pipe is bytes; types are an optimization two willing stages opt into.

---

## 6. What the POC proves

The proof of this architecture is a **shell, in miniature, in Dart** — not a simulation of any coreutil, but of the shell's own act of wiring processes. Concretely:

1. Take a trivial pipeline of real binaries — `cat foo.txt | sort | cut -f1 | wc -l` — and wire it in Dart with `Process.start` + `addStream` (§2). It must produce what the shell produces.
2. Replace one stage with a fake `implements Process` and change *nothing else in the wiring* (§3). The output must be identical. That is fusion proven.
3. The first *real* coreutil to build on the validated harness is **`tee`** — the fan-out shape — because it is exactly the node the linear-pipeline intuition does not cover, and the POC's own wiring is what exercises its branches (§4).

If steps 1–2 hold, the thesis holds: command and pipe are `Process` and `Pipe`, the shell is wiring, and fusion is a swapped constructor. Then the catalog is built — and consolidated into the parent package — against a concept that is no longer asserted but demonstrated.

---

*Thesis: [coreutil-lib-interface.md](coreutil-lib-interface.md). This document is its architecture. The catalog and the compositions stand on both.*
