# The userland — composing capabilities as pipeline jobs

**What this is.** BentOS exposes each external capability as an OS device — the platform thesis: `open("/dev/llm/…")` is as much a given as `open()` itself. The *userland* is the layer above: a set of coreutils — small programs, one capability each — that **compose into workflows through OS primitives**, pipes and processes, rather than through a framework runtime. It is the same problem LangChain, LangGraph, and n8n attack — chaining capabilities into a working pipeline — solved **OS-based instead of framework-based**.

This document is the thesis: the idea and its primitives. The architecture that realizes it — the concrete `dart:io` interfaces a pipeline job is built from — is the companion [pipeline-jobs.md](pipeline-jobs.md). The catalog of specific coreutils and the workflows they compose are authored elsewhere, each in isolation (§6). Standing under all of it: [../../bentos/platform-thesis.md](../../bentos/platform-thesis.md) — the device layer.

---

## 1. The job: a pipeline of commands joined by pipes

The ontology we model is the oldest one in the craft — the **pipeline job**, `A | B | C`. It has exactly two primitives:

- **command** — the node. A stage of the pipeline: a unit with input and output channels, arguments, and an operation. The classic Unix *filter* — read stdin, write stdout — is its commonest shape, but not its definition (§3).
- **pipe** — the connector. A unidirectional channel carrying one command's output into the next's input. `|`.

A workflow is nothing but commands wired by pipes. That is the whole substrate.

**The plumbing is semantics-blind, and that is the point.** A pipe does not know — must not know — what flows through it. It carries data; the meaning of that data is the command's business, never the pipe's. This is why one plumbing serves every domain: the same `|` that wires text utilities wires inference, voice, vision, embeddings. The composition layer is generic precisely because it refuses to look inside the payload.

**Blind, but not untyped.** In shell the payload is bytes; in a fused, in-language pipeline ([pipeline-jobs.md §5](pipeline-jobs.md)) two adjacent stages may pass a live value. The plumbing stays generic by being *parametric* — generic over the element type, carrying it end to end without interpreting it. Semantics-blind and type-safe are the same property seen from two sides: the pipe knows the type's *shape* well enough to carry it, and its *meaning* not at all.

---

## 2. OS-based, not framework-based

Place the framework world beside this and the correspondence is exact — and deflationary:

| Framework | This |
|---|---|
| the chain / the pipe operator | the OS **pipe**, `\|` |
| a node | a **command** (a process) |
| the graph DSL (control flow) | a **program** — shell, Python, Dart, a binary |
| the runtime that hosts the graph | **no runtime** — the OS runs processes; your program is the orchestration |

A framework simulates *inside a single runtime* what the operating system already provides natively: composition, concurrency, dataflow. It must, because the real primitives are absent from its platform. We do not simulate them — we *have* them. The pipe is the kernel's pipe. The "workflow DSL" is just a script, in whatever language you already speak; its control flow — the loops, the branches, the decision on a tool result — is the host language's own, not a bespoke graph engine. There is no inversion of control: your code owns the loop; nothing hosts you.

> The framework's value proposition is the composition it adds. On an OS where composition is free, that value proposition is the OS.

---

## 3. Command shapes — one concept, several arities

Treating every command as a stdin→stdout filter is the trap; it forces the genuinely different shapes into special cases. A command is characterized by its arity over input and output channels:

| shape | signature | role |
|---|---|---|
| **source** | `() → Stream<O>` | produces a stream from arguments; no input |
| **filter** | `Stream<I> → Stream<O>` | the canonical transformer; one in, one out |
| **sink** | `Stream<I> → Future<void>` | consumes; terminal, no downstream |
| **reducer** | `Stream<I> → Future<O>` | folds a stream to a single value |
| **fan-out** | `Stream<I> → Stream<I>` (+ side channels) | duplicates the stream; `tee` is the archetype |

All five are commands; all five wire by pipe — though fan-out is where the line becomes a graph: its side channels are simply additional output pipes, the branch points where one stream feeds more than one downstream. The filter is merely the one in the middle of `A | B | C`. Designing the userland around *command* rather than *filter* is what lets a producer, a fold, or a `tee` compose as uniformly as any filter — instead of arriving as exceptions to be special-cased. That these five are not five interfaces but one — a single node type touching different channels — is the architecture's to show ([pipeline-jobs.md §4](pipeline-jobs.md)).

---

## 4. Two modes: prototype as CLI, solidify as library

Every coreutil exists in two consumable forms, and the relationship between them is the reason the library form exists at all.

- **As a CLI executable** — the prototyping material. You wire a workflow by composing programs with `|` at a shell, run it, adjust it. Fast, inspectable, `cat`-able, disposable.
- **As a library block** — the production material. The same coreutil, imported in-process, lets you **fuse** that prototyped pipeline into a single program — or a compiled binary — with the *same wiring*. Each `|` becomes an in-language composition; the subprocesses collapse into one.

The progression is shell → script → binary: prototype the workflow in the softest material, then forge it in one as solid as you need — for performance, for deployment, for distribution. The acceptance test that governs the library design is literal: **the fused pipeline must mirror the shell pipeline line for line** — `|` becomes a composition, and nothing else moves. If the in-language wiring does not read like the pipe it replaces, the library interface is wrong.

**What the fusion changes — and why it is a gain.** The shell pipeline is concurrent processes coupled by kernel buffers, with backpressure expressed as blocking I/O. The fused pipeline is a single cooperative dataflow in one process: one thread, deterministic ordering, no kernel buffer, no IPC. It trades OS-process parallelism for in-process cooperative concurrency — and for these workflows that is pure gain, because their cost is I/O wait (a device answering) not CPU contention. Parallelism across cores buys nothing when there is no CPU work competing; determinism, single-process deployment, and a tight I/O boundary buy a great deal. The rule that falls out: **asynchrony lives only at the real I/O boundary** — the device, the sinks — while the entire transforming middle is synchronous, each value passing through promptly and in order.

What fusion does *not* do by itself is erase the per-stage encode/decode: the base channel is bytes, so adjacent stages still serialize across it. That cost is negligible here — these pipelines pay in latency, not codecs — and where two cooperating stages want to skip it, a typed port lets them. That is an optimization the architecture defines, not a property of fusion; [pipeline-jobs.md §5](pipeline-jobs.md) draws the line.

---

## 5. Any workflow, any domain

The substrate is indifferent to what it composes. A pipeline job may be:

- **any AI domain** — not inference alone. One subsystem per capability class (the platform thesis): voice, vision, image, video, segmentation, embeddings — each a device, each a command in reach of a pipe. `stt | llm | tts` is not a demo; it is how the machine composes.
- **AI or not at all.** The same primitives wire a log filter, a report builder, a deploy script. Intelligence is one kind of command among many, not a category apart.

The familiar AI workflows are **compositions that emerge from these primitives, not primitives themselves**:

- an *llm turn* is one inference cycle — a pipeline with `llm` in the middle;
- an *agent turn* is that, wrapped in a loop that re-enters on tool calls and exits when the model returns a final answer with none — the agent goes idle. The classic ReAct loop, and nothing more than a `while` your program owns.

Both are *examples*. Assuming either shape here would be the contamination this document refuses: the substrate must not take on the form of any one job built on it. Those shapes are authored in their own documents, downstream.

---

## 6. What follows

This document is the thesis; [pipeline-jobs.md](pipeline-jobs.md) is its architecture. Two further bodies of work stand on both, each authored in isolation so neither contaminates the model:

- **the catalog** — each coreutil specified on its own terms: its capability, its command shape, its CLI and library surface;
- **the compositions** — concrete workflows (the llm turn, the agent turn, and others) built from the catalog.

The primitive is the pipe; the material is the command; the workflow is the program you write with them. That is the userland.
