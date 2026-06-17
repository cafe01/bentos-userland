# `tx` — state across time

```sh
tx repo new cafe             # open a being's repository (john/cafe)
tx timeline fork explore     # branch a what-if, parallel and live
tx commit -m "user turn"     # journal one mutation of your state
tx rewind 3                  # walk the state back three commits
```

`tx` is the **stateful half of Unix composition**. The pipe composes programs *in the instant* — a stream from one stdout to the next stdin, data carried *now* between processes running *now*, then gone. There was never a universal interface for **durable, forkable, time-travelable** state; every program that needed it rolled its own file format. `tx` is that missing half: one ontology of state — **`git`, raised into userland** — shared by every program on the box.

> [!IMPORTANT]
> **The pipe is the stateless half of composition; `tx` is the stateful half.**
> - **pipe** — universal *dataflow* interface; synergy in the moment.
> - **`tx`** — universal *state* interface; synergy across the timeline (fork, rewind, history, parallelism).
>
> A pure stateless program (a calculator) needs no `tx`; every program that *has* a state now has the *same* one — one transactional substrate instead of N bespoke session stores.

But `tx` is more than `git` renamed. It manages many beings, each owning many repositories, each branching into many parallel timelines. The right reference for the UX is not bare `git` — it is **`gh`**: a *host*, with owners, repositories, and a clean split between managing the repository and working inside it. `tx` is that host, projected onto our ontology.

---

## The one idea: your state is a directory

Hold this before anything else, because every command follows from it.

**Your state is a directory on disk** — a *worktree* — that you read and write with any tool you like. The *history* of how it got there is git's job: the commit DAG. `tx` versions that directory, branches it, rewinds it, and runs many copies of it in parallel. It never looks inside your files.

The consequence is sharp: **the state machine is yours; `tx` is only the substrate.** In principle your program would work writing straight to a plain directory — read it, mutate it, done. `tx` is what turns that plain directory into a *versioned, forkable, parallel* one. Take `tx` away and the program still runs; it just loses time-travel, branching, and concurrency.

This is the correction that defines the redesign. State is **not** an append-only log you re-fold to reconstruct the present — a file that grows forever and costs O(n) to read. State is the **materialized directory, sitting there, ready**. Reading it is reading a directory; there is no replay. Git already keeps the worktree materialized for you; re-implementing that as a growing log on top of git was doing the same job twice.

> [!NOTE]
> **Append-only is the degenerate case, not the model.** A chat's state only ever grows — `List<ChatMessage>` — so its every mutation is "append a line, then commit." That is one shape of state machine, the simplest. A richer one edits, restructures, and **shrinks** its state — and shrinking is something an append-only log can never express, while a materialized directory expresses it for free (the diff records what left). `tx` serves both because it is blind to which one you are.

---

## The four axes

`tx` addresses state along four axes, outermost to innermost. The first three are the GitHub coordinate; the fourth is its materialization.

| axis | what it is | GitHub analog | git analog |
|---|---|---|---|
| **entity** | the being that owns the state | the owner (`owner/…`) | — |
| **repo** | one independent existence of that being | the repository (`…/repo`) | a repository |
| **timeline** | a branch of that existence | a branch | a branch |
| **worktree** | a timeline made real, as a directory | a checkout | a worktree |

The address of any state is **`entity/repo@timeline`**, materialized at a worktree path.

**Why `repo` and `timeline` are different axes — and not one.** The temptation is to drop `repo` and encode everything in the timeline name. That would be a lie about ancestry. Two *timelines* of one repo share a root and **can merge** — they are branches of one history. Two *repos* share nothing and **never merge** — they are unrelated existences. So `john`'s work-with-cafe and work-with-alfred must be two repos — `john/cafe` and `john/alfred` — not two timeline names: collapsing them into timelines would falsely claim they share ancestry and could be merged. `repo` is not a luxury axis; it is the axis that keeps unrelated lives honestly separate.

> [!NOTE]
> **The entity is a being, never a user or a directory.** `john`'s repos are *John's* — his life-ledger. Fork and time-travel are not features bolted on; they are **properties of an existence on disk**, available precisely because a digital being's self *is* the disk. A human at the keyboard is the **operator**, never an entity: `cafe` has no repos, cannot fork, cannot rewind. He names the being he addresses.

The entity is resolved, and the state is rooted, exactly like `.mem`:

```
entity = --entity <name> ?? --agent <name> ?? $BENTOS_AGENT
root   = the governing place (walk up for place.yaml) → <place>/.tx/<entity>/<repo>/
```

The body exports `$BENTOS_AGENT` at spawn, so a live being's `tx` defaults to *its own* state — operating on itself, the **hydra** case (mirroring `claude-spawn <name>`: the same name is a head of yourself, another name is a peer). There is no fallback to the operator: a human in a raw shell must name the being (`tx --entity john …`), or `tx` errors asking which one. `.tx/<entity>/` and `.mem/<entity>/` always land together, found by the same hierarchy.

---

## Walkthrough

### Open a repository

```sh
tx repo new cafe               # create john/cafe; it starts with one timeline, 'main'
tx repo ls                     # the entity's repositories
```

`tx repo new` is a *repository* operation — it brings a whole new existence into being. Keep it mentally apart from the day-to-day; it is the rare act, like `gh repo create`, not something a turn does.

### Your state is the worktree — write to it, then journal

A repo's `main` timeline is materialized at a worktree. Ask where it is, and write your state there with ordinary tools:

```sh
cd "$(tx timeline path main)"          # the worktree directory — your state lives here
echo '{"role":"user","content":"hi"}' >> record   # the app mutates its own state, directly
```

When your state machine has advanced — appended, edited, shrunk, anything — you journal that step as one commit:

```sh
tx commit -m "user turn"
```

One mutation, one commit: the write-ahead property, so every step is a durable point you can return to. Note what `tx` did *not* do: it never read or wrote the *content* of `record`. You did. `tx` only versioned the directory.

> [!IMPORTANT]
> **`tx` is out of the mutation business — there is no `cat`, no `append`.** The old surface streamed your bytes in and out (`tx append`/`tx cat`); the app and `tx` argued over framing. Gone. The app reads and writes the worktree directly, with whatever tools fit its state; `tx` only commits, branches, and rewinds the directory. This is stronger content-blindness than before: `tx` does not even *transport* your content, let alone parse it.

### Look back, and go back

```sh
tx log               # this timeline's commit trace
tx rewind 1          # reset the worktree back one commit — time travel
```

`rewind` counts **commits**, not turns — `tx` knows only commits. Anything turn-granular (a chat "session" is a `tx` timeline; a chat "turn" is several commits) is the consumer's sugar, never `tx`'s.

### Run timelines in parallel — the unlock

This is why the worktree model exists, and why bare branches were not enough: a branch you must `checkout` into is a branch that *un-materializes* the others. We need them all live at once.

```sh
tx timeline new head-a       # its own directory, materialized
tx timeline new head-b       # a second, independent directory
tx timeline ls
# * head-a   /…/.tx/john/cafe/head-a
#   head-b   /…/.tx/john/cafe/head-b
#   main     /…/.tx/john/cafe/main
```

Three directories, all materialized simultaneously (plain `git worktree` underneath — one repo, many working directories). Two workers can mutate `head-a` and `head-b` at the same time, each committing its own line, neither touching the other — the hydra, made of real directories. **Which timeline a command acts on is decided by the worktree you run it from**; there is no hidden "current" to switch.

### Branch a tangent, fold it back

```sh
tx timeline fork explore main      # 'explore' starts as a copy of main's state, then diverges
# … work in explore's worktree …
tx timeline merge explore main     # fold explore's result back into main
```

`fork` is cheap — git shares the unchanged history structurally. `main` never notices `explore` until the merge.

### Many existences for one being

The `repo` axis at work — the same being, two unrelated lives:

```sh
tx repo new cafe                   # john/cafe   — john, working with cafe
tx repo new alfred                 # john/alfred — working with alfred; separate root, separate history
tx repo ls                         # both, owned by entity 'john'
```

### Tear down

```sh
tx timeline rm explore             # remove a timeline's worktree (history stays in the repo)
tx repo rm cafe                    # remove an entire existence (john/cafe)
```

---

## The command surface

Three groups, the `gh` shape: nouns for topology, bare verbs for the daily work inside a timeline.

**Repository** — operations on an existence itself (rare):

| command | does | git underneath |
|---|---|---|
| `tx repo new <name>` | create a repo (+ a `main` timeline) | `init` + first worktree |
| `tx repo ls` | the entity's repositories | — |
| `tx repo rm <name>` | remove an entire existence | — |

**Timeline** — operations on branches and their worktrees:

| command | does | git underneath |
|---|---|---|
| `tx timeline new <name>` | new branch + materialized worktree | `worktree add` (new branch) |
| `tx timeline ls` | timelines + their live worktree paths | `worktree list` |
| `tx timeline path [<name>]` | print a timeline's worktree directory | `worktree list` |
| `tx timeline fork <new> [<src>]` | branch a new parallel timeline from `src` | `worktree add` (from branch) |
| `tx timeline merge <src> [<dst>]` | fold one timeline's result into another | `merge` |
| `tx timeline rm <name>` | tear down a timeline's worktree | `worktree remove` |

**Day to day** — verbs acting on the worktree you are in:

| command | does | git underneath |
|---|---|---|
| `tx commit [-m <msg>]` | journal the current worktree state as one mutation | `add -A && commit` |
| `tx log` | this timeline's commit trace | `log --oneline` |
| `tx rewind <n>` | reset the worktree back `n` commits | `reset --hard HEAD~n` |

All scoped by `--entity`/`--agent`/`$BENTOS_AGENT`, rooted at the governing place.

> [!TIP]
> **The vocabulary may become ours; the effect stays git's.** We do not pin what a timeline *means* one floor up — a thread, a what-if, a being's context. We define only the effect, which is git's: a fork is a new line, commits stack, rewind goes back, merge folds in. Pinning the meaning early would be the same error as reading inside the file. `tx` abstains from content and from interpretation alike.

---

## The DAG is git, not the file

> [!NOTE]
> Claude's session `.jsonl` smears a tree into a flat file — a `parentUuid` on every line, the topology serialized by hand into the record. We don't. Our state is a plain directory; the DAG — fork, rewind, merge, parallel timelines — **is git's commit graph itself.** Nothing about branching touches the content, and nothing about the content constrains branching. That separation is the whole reason one `tx` serves chat, voice, vision, or any future state machine unchanged.

---

## Design decisions left open

Surfaced honestly, to be settled as consumers exercise them.

- **Commit granularity — who fires `tx commit`?** The lean is the app: the state machine decides what one mutation is and commits explicitly, keeping the app↔`tx` boundary clean and atomicity app-defined. The alternative — `tx` watching the worktree and auto-committing — couples `tx` to the app's rhythm. Lean: explicit, app-driven.
- **The on-disk layout of repo vs. worktrees.** A repo is a bare git store at `<place>/.tx/<entity>/<repo>/.git` with each timeline a linked worktree sibling `<place>/.tx/<entity>/<repo>/<timeline>/` — so no timeline is privileged and all are equal, parallel checkouts. The exact bare-vs-primary detail is the one internal junction to confirm before code.
- **`merge` in v1?** Listed as a generic capability now. Whether it ships in the first cut or waits for a consumer that genuinely folds timelines back is open — it is the one verb without a forcing use case yet at this altitude.

---

## Authority

- The paradigm `tx` completes (the two halves of composition, state-in-the-place) — `hq/workshop/humanos/userland/the-userland-paradigm.md`
- The thread/timeline engine design (the spec) — `hq/workshop/bentos-agent/design/session-and-txlog.md`
- The entity repo as microcosm (conceptual lineage, *not* a spec) — `books/bentos-agent/13-the-transaction-log.md`
- General coreutil principles + the category map — `../README.md`
