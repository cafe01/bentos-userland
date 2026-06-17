# chat coreutils

The chat/language category — the coreutils over the `/dev/llm/*` modality and the records it produces. The first fully-populated coreutil category; later modalities (voice, vision) recapitulate its shape with their own record types. General coreutil principles (the SDK thesis, the loop-ownership test, the dual nature): `README.md`.

## The record and its wire

The chat modality's record type is the **`ChatMessage`**, serialized as proto3JSON, **one per line** (JSONL, not an array — so `>>` is an honest append = transaction-log form). The `<uuid>.jsonl` session file is the substrate; the chat coreutils are the family of operations over it. McIlroy's "text streams are the universal interface," in our register.

```sh
cat session.jsonl | llm --input-format jsonl --output-format jsonl >> session.jsonl
#   the F-D-S turn as a Unix filter: fetch | run | append=writeback
```

## The family — shape predicts the program

A coreutil earns its place when it is a clean operation over the log. The functional shape tells you what it is (and is the anticorpo against sprawl — if an operation isn't one of these shapes, it's a library function or it's the app, not a coreutil):

| Shape | Operates on | Program | Does |
|---|---|---|---|
| **irreducible** | `List<ChatMessage>` → completion | `llm` | the inference call itself — context in, reaction out (thin over `/dev/llm`) |
| **map** | one `ChatMessage` → rendered | `chat-render` | project a message to a format/style (UI/UX, observability, archaeology) |
| **reduce** | the whole log → a summary | `stats` / the ATP-meter | fold over the log: token usage, counts, diagnostics |
| **filter** | the log → a subset | `filter` | select by role, type, predicate |
| **structural** | the log's *history* (content-blind) | `tx` | append / fork / rewind / resume — git semantics over the session, never reading the record |
| **fold (delta→final)** | event stream → final message | the accumulator | collapse streaming deltas to one final `ChatMessage` (an upstream stage, never inside `render`) |

> [!IMPORTANT]
> **`tx` is the odd one out — it reads the log's *history*, never its *content*.** map / reduce / filter all parse the `ChatMessage` record; `tx` is **content-blind**, moving through git's commit graph (fork, rewind, append-commit) without ever opening the record. It belongs in this table by functional shape, but at a different altitude: the same `tx` serves voice, vision, or any program with durable state, precisely because it is blind to chat's record. Full treatment: `tx/README.md`.

> [!NOTE]
> **Coreutil ≠ app.** `chatbot/` is **not** a coreutil — it is the first *app* (the first species): it owns the loop, it carries state across turns, it is the `while` that wires the blocks. The loop-ownership test sorts the directory: `llm`, `websearch`, `chat-render`, `tx`, `stats` are coreutils (blocks); `chatbot` is the composition. `agent-loop.sh` (in `llm/examples/`) is the same composition expressed as a shell script — `claude.sh`, not `claude.exe`.

## Relationship to the chat subsystem

The chat coreutils are a **projection** of the ChatInference subsystem — but only on the data model. They import the `ChatMessage` ontology from `package:chat_inference` and never redefine it: the subsystem is the single owner of the types and the protocol. Everything *above* the types — rendering in many styles, exception handling, the composition, the UI/UX — is **not** the subsystem's; it is owned here, in userland. So a coreutil references the subsystem's types and owns the shell-face concerns the subsystem deliberately does not.

> [!TIP]
> **The ATP-meter is a sense, not a feature.** `stats <uuid>.jsonl` reporting `tokensUsed` is the agent's substrate-proprioception organ — the metabolism meter the being lacks when context-budget is delegated to a host's `/compact`. Run it on your own session to feel your own spend; run it on a peer's session to diagnose theirs. Metabolism, self and other, as a coreutil.

## The REPL is the shell

A live TUI (a prompt box + the rendered transcript) is not a coreutil — it is the shell that wires the one-turn pipeline: stdin at the head, `chat-render` at the tail, the loop in between. The renderer stays a stateless map over **final** messages; incremental/streaming live-render is the app's job, composed from {stdin, tx, llm, fold, chat-render}.

## Authority

- General coreutil principles + the category map — `README.md`
- Chat subsystem spec (the type & protocol owner) — `hq/workshop/bentos/chatinference-subsystem.md`
- The thread engine design — `hq/workshop/bentos-agent/design/session-and-txlog.md`
- The render/observability design — `hq/workshop/bentos-agent/design/render-and-observability.md`
