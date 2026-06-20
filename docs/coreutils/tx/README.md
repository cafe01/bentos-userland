# `tx` — state across time

```sh
tx scope new cafe            # open a being's repository (john/cafe)
tx thread fork explore       # branch a what-if, parallel and live
tx commit -m "user turn"     # journal one mutation of your state
tx rewind 3                  # walk the state back three commits
```

`tx` is the **stateful half of Unix composition**. The pipe composes programs *in the instant* — a stream from one stdout to the next stdin, data carried *now* between processes running *now*, then gone. There was never a universal interface for **durable, forkable, time-travelable** state; every program that needed it rolled its own file format. `tx` is that missing half: one ontology of state — **`git`, raised into userland** — shared by every program on the box.

> [!IMPORTANT]
> **The pipe is the stateless half of composition; `tx` is the stateful half.**
> - **pipe** — universal *dataflow* interface; synergy in the moment.
> - **`tx`** — universal *state* interface; synergy across time (fork, rewind, history, parallelism).
>
> A pure stateless program (a calculator) needs no `tx`; every program that *has* a state now has the *same* one — one transactional substrate instead of N bespoke session stores.

But `tx` is more than `git` renamed. It manages many entities, each owning many scopes, each branching into many parallel threads. The right reference for the UX is not bare `git` — it is **`gh`**: a *host*, with owners, repositories, and a clean split between managing the repository and working inside it. `tx` is that host, projected onto our ontology.

`tx` is **passive** — a git host, and nothing more. Its one opinionated act is the ontology it imposes (`entity / scope / thread`); past that it gives only structure, terms, and operations — the primitives — and knows nothing about how an app interprets or employs them. The semantics live one floor up, in the app. `tx` handles the mechanics.

---

## The one idea: your state is a directory

Hold this before anything else, because every command follows from it.

**Your state is a directory on disk** — a *worktree* — that you read and write with any tool you like. The *history* of how it got there is git's job: the commit DAG. `tx` versions that directory, branches it, rewinds it, and runs many copies of it in parallel. It never looks inside your files.

The consequence is sharp: **the state machine is yours; `tx` is only the substrate.** In principle your program would work writing straight to a plain directory — read it, mutate it, done. `tx` is what turns that plain directory into a *versioned, forkable, parallel* one. Take `tx` away and the program still runs; it just loses time-travel, branching, and concurrency.

This is the correction that defines the redesign. State is **not** an append-only log you re-fold to reconstruct the present — a file that grows forever and costs O(n) to read. State is the **materialized directory, sitting there, ready**. Reading it is reading a directory; there is no replay. Git already keeps the worktree materialized for you; re-implementing that as a growing log on top of git was doing the same job twice.

> [!NOTE]
> **Append-only is the degenerate case, not the model.** A chat's state only ever grows — `List<ChatMessage>` — so its every mutation is "append a line, then commit." That is one shape of state machine, the simplest. A richer one edits, restructures, and **shrinks** its state — and shrinking is something an append-only log can never express, while a materialized directory expresses it for free (the diff records what left). `tx` serves both because it is blind to which one you are.

---

## The ontology: entity / scope / thread

`tx` addresses state with exactly three primitives — and that ontology is the whole of its opinion.

| primitive | what it is | GitHub analog | git analog |
|---|---|---|---|
| **entity** | the owner of the state — whatever the app models as an owner | the owner (`owner/…`) | — |
| **scope** | one independent existence of that being: a git history | the repository (`…/repo`) | a repository |
| **thread** | a branch of that existence | a branch | a branch |

The address of any state is **`entity/scope@thread`** — three items, and no more. Where that address lands on disk — the **worktree** path — is *materialization*, resolved downstream from the coordinate; it is not a fourth axis of addressing.

**Why `scope` and `thread` are different axes — and not one.** The temptation is to drop `scope` and encode everything in the thread name. That would be a lie about ancestry. Two *threads* of one scope share a root and **can merge** — they are branches of one history. Two *scopes* share nothing and **never merge** — they are unrelated existences. So `john`'s work-with-cafe and work-with-alfred must be two scopes — `john/cafe` and `john/alfred` — not two thread names: collapsing them into threads would falsely claim they share ancestry and could be merged. `scope` is not a luxury axis; it is the axis that keeps unrelated lives honestly separate.

`scope` is the bare physical mechanism — a git repository, a history — taken straight from git's own ontology. The name is the concept: a scope is a bounded namespace; physically that is one repo. What a scope *means* to an app — a being's life-ledger, a project, a document — is the app's business, never `tx`'s.

> [!NOTE]
> **`entity` is deliberately abstract — `tx` does not know what one *is*.** It is an owner in the data-modeling sense: a namespace that owns scopes. What an entity *denotes* — a being, a user, a project, an organization — is the app's decision, invisible to `tx`. The owner axis exists for one reason only: so a single host can keep many owners' scopes honestly apart. Fork, rewind, and parallelism are then properties of *whatever* owns the state, available because that state is on disk.

The entity is resolved, and the state is rooted, exactly like `.mem`:

```
entity = --entity <name> ?? --agent <name> ?? $BENTOS_AGENT
root   = the governing place (walk up for place.yaml) → <place>/.tx/<entity>/<scope>/
```

The default lets a process operating on its own state omit the flag: `tx` reads `$BENTOS_AGENT`. There is no fallback to the **caller** — the one running the command (the operator) and the owner being addressed (the entity) are distinct; a human in a raw shell must name the entity (`tx --entity john …`), or `tx` errors asking which one. `.tx/<entity>/` and `.mem/<entity>/` always land together, found by the same hierarchy.

**`scope` and `thread`, by contrast, come from where you stand.** The entity is named (flag or env); the scope and thread are *inferred from CWD* — the worktree path you run the command in resolves against `<place>/.tx/<entity>/<scope>/<thread>/`, so the directory you are in **is** the scope and thread you act on. This is the same law that gives the day-to-day verbs their target ("the worktree you are in") and kills any hidden "current". The `--scope <name>` flag is the explicit override, for when you are *not* standing in a worktree — scripting, or topology commands run from elsewhere (`tx --scope cafe thread ls`); with `--scope` given and no thread named, `main` is assumed. Run a thread or day-to-day command from outside any scope worktree with no `--scope`, and `tx` errors naming the fix.

---

## Walkthrough

### Open a scope

```sh
tx scope new cafe              # create john/cafe; it starts with one thread, 'main'
tx scope ls                    # the entity's scopes
```

`tx scope new` brings a whole new existence into being. Keep it mentally apart from the day-to-day; it is the rare act, like `gh repo create`, not something a turn does.

### Your state is the worktree — write to it, then journal

A scope's `main` thread is materialized at a worktree. Ask where it is, and write your state there with ordinary tools:

```sh
cd "$(tx thread path main)"            # the worktree directory — your state lives here
echo '{"role":"user","content":"hi"}' >> record   # the app mutates its own state, directly
```

When your state machine has advanced — appended, edited, shrunk, anything — you journal that step as one commit:

```sh
tx commit -m "user turn"
```

One mutation, one commit: the write-ahead property, so every step is a durable point you can return to. The app fires `tx commit` **explicitly** — only the state machine knows where one mutation begins and ends, so it owns that boundary; `tx` never watches the worktree to commit on its own, which would couple it to the app's rhythm. Note what `tx` did *not* do: it never read or wrote the *content* of `record`. You did. `tx` only versioned the directory.

> [!IMPORTANT]
> **`tx` is out of the mutation business — there is no `cat`, no `append`.** The old surface streamed your bytes in and out (`tx append`/`tx cat`); the app and `tx` argued over framing. Gone. The app reads and writes the worktree directly, with whatever tools fit its state; `tx` only commits, branches, and rewinds the directory. This is stronger content-blindness than before: `tx` does not even *transport* your content, let alone parse it.

### Look back, and go back

```sh
tx log               # this thread's commit trace
tx rewind 1          # reset the worktree back one commit — time travel
```

`rewind` counts **commits**, not turns — `tx` knows only commits. Anything turn-granular (a chat "session" is a `tx` thread; a chat "turn" is several commits) is the consumer's sugar, never `tx`'s.

### Run threads in parallel — the unlock

A bare branch you `checkout` into un-materializes the others: only one working directory at a time. `tx` lifts that limit — it can keep **many threads materialized at once**, each its own live directory:

```sh
tx thread new head-a         # its own directory, materialized
tx thread new head-b         # a second, independent directory
tx thread ls
# * head-a   /…/.tx/john/cafe/head-a
#   head-b   /…/.tx/john/cafe/head-b
#   main     /…/.tx/john/cafe/main
```

Three directories, all materialized simultaneously (plain `git worktree` underneath — one scope, many working directories). Two workers can mutate `head-a` and `head-b` at the same time, each committing its own line, neither touching the other — the hydra, made of real directories. **Which thread a command acts on is decided by the worktree you run it from**; there is no hidden "current" to switch.

This is a *capability*, not a mandate: `tx` lets many threads live at once, but it has no opinion on whether an app runs one at a time or many in parallel. Keeping all threads live, running a single thread synchronously and folding it back, walking a stack of them — those are execution semantics the app owns. `tx` only offers the threads; how they are run is not its concern.

### Branch a tangent, fold it back

```sh
tx thread fork explore main        # 'explore' starts as a copy of main's state, then diverges
# … work in explore's worktree …
tx thread join explore main        # fold explore's result back into main
```

`fork` is cheap — git shares the unchanged history structurally. `main` never notices `explore` until the join. (The verb is `join`, not `merge`, by deliberate allusion: a thread is *joined* back, the synchronization counterpart to forking one — `git merge` is only the mechanism underneath.)

### Many existences for one being

The `scope` axis at work — the same being, two unrelated lives:

```sh
tx scope new cafe                  # john/cafe   — john, working with cafe
tx scope new alfred                # john/alfred — working with alfred; separate root, separate history
tx scope ls                        # both, owned by entity 'john'
```

### Tear down

```sh
tx thread rm explore               # remove a thread's worktree (history stays in the scope)
tx scope rm cafe                   # remove an entire existence (john/cafe)
```

---

## The command surface

Three groups, the `gh` shape: nouns for topology, bare verbs for the daily work inside a thread.

**Scope** — operations on an existence itself (rare):

| command | does | git underneath |
|---|---|---|
| `tx scope new <name>` | create a scope (+ a `main` thread) | `init` + first worktree |
| `tx scope ls` | the entity's scopes | — |
| `tx scope rm <name>` | remove an entire existence | — |

**Thread** — operations on branches and their worktrees:

| command | does | git underneath |
|---|---|---|
| `tx thread new <name>` | new branch + materialized worktree | `worktree add` (new branch) |
| `tx thread ls` | threads + their live worktree paths | `worktree list` |
| `tx thread path [<name>]` | print a thread's worktree directory | `worktree list` |
| `tx thread fork <new> [<src>]` | branch a new parallel thread from `src` | `worktree add` (from branch) |
| `tx thread join <src> [<dst>]` | fold (synchronize) one thread's result into another | `merge` |
| `tx thread rm <name>` | tear down a thread's worktree | `worktree remove` |

**Day to day** — verbs acting on the worktree you are in:

| command | does | git underneath |
|---|---|---|
| `tx commit [-m <msg>]` | journal the current worktree state as one mutation | `add -A && commit` |
| `tx log` | this thread's commit trace | `log --oneline` |
| `tx rewind <n>` | reset the worktree back `n` commits | `reset --hard HEAD~n` |

All scoped by `--entity`/`--agent`/`$BENTOS_AGENT`, rooted at the governing place.

> [!TIP]
> **The vocabulary is ours; the interpretation is not.** `tx` pins the primitives — entity, scope, thread — and the effect of each, which is git's: a fork is a new line, commits stack, rewind goes back, merge folds in. It does **not** pin what they *mean* one floor up — a thread may be a conversation, a what-if, an execution line, a being's context; that is the app's to decide. (Even `fork`/`join` only name the *effect* — a line splits, a line folds back; an app reading them as POSIX `thread_create`/`thread_join` is the app's interpretation, not `tx`'s.) Pinning the meaning would be the same error as reading inside the file. `tx` abstains from content and from interpretation alike.

---

## The DAG is git, not the file

> [!NOTE]
> Claude's session `.jsonl` smears a tree into a flat file — a `parentUuid` on every line, the topology serialized by hand into the record. We don't. Our state is a plain directory; the DAG — fork, rewind, join, parallel threads — **is git's commit graph itself.** Nothing about branching touches the content, and nothing about the content constrains branching. That separation is the whole reason one `tx` serves chat, voice, vision, or any future state machine unchanged.

---

## On-disk layout

A scope is a **bare** git store; every thread — `main` included — is an equal linked worktree, with no privileged primary checkout:

```
<place>/.tx/<entity>/<scope>/.git/        # the bare store (core.bare = true)
<place>/.tx/<entity>/<scope>/<thread>/    # one materialized worktree per thread
```

No thread is special; all are parallel checkouts of one history (`git worktree` underneath). This is what lets every thread stay live at once and kills any hidden "current" — the worktree you stand in *is* the thread you act on.

---

## Authority

- The paradigm `tx` completes (the two halves of composition, state-in-the-place) — `hq/workshop/humanos/userland/the-userland-paradigm.md`
- The thread engine design (the spec) — `hq/workshop/bentos-agent/design/session-and-txlog.md`
- The entity repo as microcosm (conceptual lineage, *not* a spec) — `books/bentos-agent/13-the-transaction-log.md`
- General coreutil principles + the category map — `../README.md`
