> [!CAUTION]
> **SUPERSEDED — this coreutil no longer exists.** `chat` is now an *application*, not a one-turn coreutil. A turn is a step *inside* the app (a composition of `llm`, `chat-codec`, and `chat-render` over `tx`), never a command you call. This whole doc — and the `coreutils/chat` directory — dies when the chat app ships. Source of truth: `hq/workshop/humanos/apps/chat/product.md` and `engineering.md`; user-facing face: `../../apps/chat/README.md`. Everything below is the dead model (and uses the retired `tx cat`/`append` surface); do not build against it.

# `chat` — the turn as a command

```sh
chat "what shipped in the latest stable Dart release?"
```

`chat` is one **turn**: input at the head, the model (and its tools) in the middle, the reply streamed at the tail — then it exits. It holds no credentials and knows no provider; it opens a device (`/dev/llm/<vendor>/<model>`) and appends the exchange to a being's transaction log. The provider is the driver's concern. The history is the entity's.

> [!IMPORTANT]
> **There is no REPL inside `chat` by default. The shell is the REPL.** A turn is `bash -c`; looping over turns is `bash -i` — your shell, not ours. The default `chat` runs one turn and returns to your prompt — no scrollback to manage, no `while` to run. (One opt-in convenience, `chat -i`, bundles the loop inside `chat` — the named exception; see the forms below.) You are in your normal shell *and* with the agent at the same time — the agent is not a mode you enter and exit, it is a command ambient in your shell.

---

## The turn against an ambient session

Each `chat` invocation is one turn against the **current session** of an entity. Continuity across invocations is not held in memory — it lives on disk, in the entity's `tx` log. At the head of the turn `chat` reads the accumulated session (`tx cat`) and **decodes** the opaque bytes into `List<ChatMessage>` — only `chat` speaks the record. It runs the turn, then **encodes** each mutation back to bytes and **appends** it (`tx append`), owning the JSONL framing throughout. The next `chat` picks up exactly where it left off. Running `chat` repeatedly *is* the conversation; the loop is the shell's.

> [!NOTE]
> **`tx` supersedes the bespoke session store.** The `chatbot` base species shipped its own `SessionStore` (JSONL under `$XDG_DATA_HOME/chatbot/sessions`) — exactly the kind of per-program store `tx` exists to abolish ("one transactional substrate instead of N bespoke session stores"). `chat` uses `tx`, never a private store; `chatbot` migrates onto `tx` as it adopts the paradigm. No two stores coexist past the transition.

```sh
chat "explain TCP vs UDP in one sentence"   # turn 1 → appended to the current session
chat "when would you choose UDP?"           # turn 2 → continues it
tx fork                                      # branch off to explore a tangent
```

Inside one turn, `chat` owns the **agent loop** — the model emits text and tool calls; the body dispatches the tools, feeds results back, and loops until the model stops (a bounded tool-iteration guard). That loop is the *eval* of a single turn and stays inside `chat`. The loop *between* turns is the shell's. Two different loops, two different owners.

---

## Whose conversation — the entity

`chat` always converses *with* a being, and the turn lands in that being's log:

```
entity = --agent <name> ?? $BENTOS_AGENT
```

- `chat -a alfred "..."` — talk to Alfred; the turn appends to `.tx/alfred/`.
- `chat -a john "..."` — talk to John; appends to `.tx/john/`.
- A live agent body (where `$BENTOS_AGENT` is exported) running `chat` with no `-a` continues *its own* session — talking to itself, which is exactly a **hydra** head. This mirrors `claude-spawn <name>`: same name continues a head of yourself; a different name addresses a peer. To converse with another being, you name it (`chat --agent john`).

The operator is never the entity: `cafe` at the keyboard names the being he addresses; there is no `.tx/cafe/`. (Full resolution and rationale: see `../tx/README.md`.)

---

## Tools — reaching outward

`chat` reaches **outward** to query the world; it never reaches **inward** to your machine. Its first tool is web search: when a question needs current or external information, it searches and uses the results. The model declares tools the way every BentOS agent does; the body executes them — the same dispatch the `llm` agent-loop proved, now inside the coreutil. The line it does not cross is the host: **no shell, no filesystem, no mutation of your system.** An agent that acts on your machine is a different species.

---

## Composition — `chat` is a coreutil, not the app

`chat` is a block, not the `while`. It produces the turn; `tx` persists it (content-blind commit); the projection family renders and folds it:

| Concern                              | Owner                                      |
| ------------------------------------ | ------------------------------------------ |
| run one turn (inference + tool loop) | `chat`                                     |
| persist / fork / rewind the history  | `tx` (commits the bytes, never reads them) |
| render a message to the terminal     | `chat-render` (the `map`)                  |
| token spend / counts (the ATP-meter) | `stats` (the `reduce`)                     |

A live conversational TUI — a prompt box plus a rendered transcript — would be the *app* that wires these blocks (`chatbot`, the base species, is exactly that). `chat` itself stays a single turn that begins and ends.

> [!NOTE]
> **The three forms — and only `-i` loops.**
> - `chat <prompt>` — one-shot, prompt from argv.
> - `chat` (bare) — **still one-shot**: it opens a prompt box, reads the one input, runs the turn, exits. No loop, no simulated REPL; the shell stays the loop. Bare changes only *where the prompt comes from*, not whether it loops.
> - `chat -i` — the thin convenience loop (the `bash -i` analog): the one place a `while` lives inside `chat`, opted into by name. Purity holds for the defaults; the loop is a named exception, never the default.

---

## Authority

- The paradigm — the shell *is* the REPL, the turn is a job — `hq/workshop/humanos/userland/the-userland-paradigm.md`
- The chat coreutils category (the record, the wire, the projection family) — `../chat.md`
- The state engine `chat` composes with — `../tx/README.md`
- General coreutil principles + the loop-ownership test — `../README.md`
