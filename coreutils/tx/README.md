# `tx` — state across time

```sh
tx fork          # branch the current session
tx rewind 3      # go back three turns
tx log           # the execution trace
```

`tx` is the **stateful half of Unix composition**. The pipe composes programs *in the instant* — a text stream from one stdout to the next stdin, data carried *now* between processes running *now*, then gone. There was never a universal interface for **durable, forkable, time-travelable** state; every program that needed it rolled its own file format. `tx` is that missing half: one ontology of transactions — **`git`, exposed as userland commands** — shared by every program on the box.

> [!IMPORTANT]
> **The pipe is the stateless half of composition; `tx` is the stateful half.**
> - **pipe** — universal *dataflow* interface; synergy in the moment.
> - **`tx`** — universal *state* interface; synergy across the timeline (fork, rewind, history).
>
> Together they are the complete composition model. A pure stateless program (a calculator) needs no `tx`; every program that *has* a session now has the *same* one — one transactional substrate instead of N bespoke session stores.

---

## The defining discipline: `tx` is content-blind

`tx` never reads inside the file. It commits, checks out, branches, rewinds — it moves through *history*, never through *meaning*. The same agnosticism git has toward your source: it versions bytes, it does not parse them.

This is the line that keeps `tx` universal. Whoever reads the *content* of a session — projects a `ChatMessage`, folds token usage, filters by role — is the projection family (`chat-render`, `stats`, `filter`), a different altitude entirely. `tx` moves the history; the family reads the message. Because `tx` is blind to the record, the **same** `tx` serves chat, voice, vision, or any future program with durable state. Branching never leaks into the record format, and the record format never constrains branching.

> [!IMPORTANT]
> **The caller owns the framing; `tx` moves opaque bytes.** A session record is a `List<ChatMessage>` framed one-per-line (JSONL), but `tx` does not know that — `tx append` takes bytes on stdin and commits them verbatim; `tx cat` streams the accumulated bytes back. The newline-per-record framing, the encode, the decode — all the caller's (`chat`'s). A content-blind layer cannot own the framing of content it refuses to read; the program that *speaks* the record owns it. (Same invariant the channel layer enforces: blind transport, caller-owned framing.)

> [!NOTE]
> **The DAG is git, not the file.** Claude's session `.jsonl` smears a tree into the file — a `parentUuid` on every line, the topology serialized by hand. We don't. Our record stays a dumb, append-only `List<ChatMessage>`; the DAG — fork, rewind, merge — **is git's commit graph itself.** Nothing about branching touches the message.

---

## The unit is the entity

A `tx` repo is scoped to a **being**, not a directory and not a user. `.tx/alfred/` is *Alfred's* transaction log — his life-ledger — co-located with `.mem/alfred/`: the place hosts it, the entity names it (the `.git`/`.mem` pattern). Fork and time-travel are not features; they are **properties of an existence on disk** — a digital being can branch, rewind, and recover from a crash precisely because its self *is* the disk. A human at the keyboard is the **operator**, never the entity: `cafe` has no `.tx/`, cannot fork, cannot rewind. The entity repo is the microcosm — the persisted life of a being.

So every `tx` operation references an entity, resolved as:

```
entity = --agent <name> ?? $BENTOS_AGENT
```

The body already exports `$BENTOS_AGENT` at spawn, so a live agent's `tx` defaults to itself. There is no fallback to the operator: a human in a raw shell must *name* the agent (`tx --agent alfred log`); without one, `tx` errors asking which being — it never writes a log for `$USER`.

> [!NOTE]
> **Place resolution mirrors `.mem`.** `<place>` is not the literal CWD — that would scatter `.tx/<entity>/` across every directory a turn runs in. `tx` resolves the place the way `.mem` does: walk up the filesystem for the governing `place.yaml`, and root the entity's repo there. The session belongs to *the place that owns the context*, found by the same hierarchy that finds memory — so `.tx/<entity>/` and `.mem/<entity>/` always land together. The resolution rule is `.mem`'s, not a second invention.

---

## The command surface

`tx` is a busybox-style multicall binary — one namespace for the state operations, the way `git` groups branch/checkout/log. The shell is the dispatcher; there is no slash-command layer to reinvent.

| Command | git analog | Does |
|---|---|---|
| `tx new` | `init` / new branch | open a fresh session, make it current |
| `tx ls` | `branch` | list sessions |
| `tx current` | `HEAD` | the current session ref |
| `tx log` | `log` | the execution trace — every committed mutation |
| `tx fork` | `branch` / `checkout -b` | branch the current session into a new line |
| `tx rewind <n>` | `reset` / `checkout` | move the current ref back **`n` commits** |
| `tx append` | `commit` | append bytes (stdin) to the current session and commit — one append, one commit (content-blind) |
| `tx cat` | `show` / `cat-file` | stream the current session's accumulated bytes to stdout (content-blind — the caller decodes) |

> [!NOTE]
> **One append, one commit — and the *caller* defines the mutation.** `tx` is blind to what a "turn" or a "mutation" is; it knows only the append. So the granularity is the caller's: `chat` issues a separate `tx append` for the user input (committed *before* inference runs — the write-ahead property, so a crash never loses the question), the assistant reaction, each tool result, the final. Every commit is a resume point, a replay point, a `git checkout`-able moment. Crash recovery is not a mechanism we build — it falls out of committing every append. `tx rewind` therefore counts **commits**, not turns; a turn-granular rewind is `chat`'s convenience (it knows the turn→commit mapping), never `tx`'s.

> [!TIP]
> **Semantics stay agnostic — on purpose.** We do not define, yet, what a branch *means* (a thread? a stack frame? a what-if?). We define only the *effect*, which is git's: fork creates a new line, commits stack on the current ref, rewind goes back. We abstained from the file's content; we abstain equally from the primitives' meaning. Pinning the semantics early would be the same error as reading inside the file. The vocabulary may become ours (`fork`/`rewind` over `branch`/`reset`); the effect is git's.

---

## Authority

- The paradigm `tx` completes (the two halves of composition, state-in-the-place) — `hq/workshop/humanos/userland/the-userland-paradigm.md`
- The thread/session engine design (the spec, when it lands) — `hq/workshop/bentos-agent/design/session-and-txlog.md`
- The entity repo as microcosm (conceptual lineage, *not* a spec) — `books/bentos-agent/13-the-transaction-log.md`
- General coreutil principles + the category map — `../README.md`
