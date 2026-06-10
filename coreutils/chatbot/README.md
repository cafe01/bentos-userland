# `chatbot` — a conversation that remembers

```sh
chatbot
```

`chatbot` is the HumanOS conversational agent. You talk; it replies; it can look things up on the web when a question reaches past what it knows. When you close it, the conversation is still there — resume it tomorrow, same thread, same context, as if you'd never left.

Under the hood it holds no credentials and knows no provider. It opens a device — `/dev/llm/<vendor>/<model>` — and every turn is appended to a **session log** the brain writes at each step. The provider is the driver's concern. The session is yours.

> [!TIP]
> `chatbot` is the **base species** every acting agent descends from: conversation, memory, and the ability to look **outward** at the world. What separates it from those agents is not the absence of tools — it is the absence of agency over your machine. A chatbot may query the world; it never runs a shell, reads your files, or touches the host.

---

## Quick start

```sh
# Start a new conversation.
chatbot

# Resume your last session.
chatbot resume

# Single-shot — an answer without opening a session.
chatbot "what is the capital of Burkina Faso?"

# It can look things up — ask about something it wouldn't know offline.
chatbot "what shipped in the latest stable Dart release?"
```

---

## Commands

### `chatbot` — open a conversation (default)

Starts a new session. Each line you type is a turn; the model replies; the exchange is appended to the session log. When you exit, the session is sealed and addressable by ID.

```
$ chatbot
> explain the difference between TCP and UDP in one sentence
TCP guarantees delivery and order; UDP doesn't — and that's often the right trade.
> when would you choose UDP?
...
> /exit
Session abc123 sealed.
```

`/exit` or `Ctrl-D` ends the session. The conversation is on disk.

| Flag | Meaning |
|---|---|
| `-d, --device <vendor/model>` | Device to open. Overrides `$BENTOS_LLM_DEVICE` and the configured default. Accepts an alias (see `llm config`). |
| `-s, --system <text>` | System prompt for this session. Repeatable — segments joined in order. |
| `-n, --name <name>` | Give this session a human name instead of an auto-generated ID. |

### `chatbot resume [session]` — continue a past session

Reopens a session. With no argument, resumes the most recent one.

```sh
chatbot resume          # last session
chatbot resume abc123   # by ID
chatbot resume work     # by name, if you used -n
```

The full history is reloaded into context; the model has everything it said before.

> [!NOTE]
> **Long sessions — the limbic answer, not auto-summarization.** A session log grows, and eventually it approaches the model's context window. `chatbot` does **not** silently summarize or truncate behind your back — the body deciding for the mind is exactly the failure mode we reject. The intended answer is *limbic*: the body senses its energy (the token budget) running low and signals the mind, which then voluntarily seals the session and continues in a fresh one — a deliberate nap, not an automatic compaction. This mechanism is designed but not yet built; until it lands, a long session simply grows.

### `chatbot list` — list sessions

```sh
$ chatbot list
abc123   2026-06-08  14 turns  "explain the difference between TCP..."
work     2026-06-07   8 turns  "let's plan the Q3 roadmap"
```

### `chatbot show <session>` — read a transcript

```sh
chatbot show abc123
chatbot show abc123 --json
```

### `chatbot fork <session> [--at <turn>]` — branch a conversation

Creates a new session from a past state. Fork from turn N to explore a different direction without losing the original thread.

> [!NOTE]
> **Gap — fork and rewind CLI shape.** The session log model supports branching structurally. How turns are addressed (numbered? timestamped?) and the exact flags are not yet designed. The capability is intentional — the design is open.

---

## Tools — reaching outward

`chatbot` can reach **outward** to query the world; it never reaches **inward** to your machine. Its first tool is **web search**: when a question needs current or external information, it searches and uses the results in its reply.

```
> what's the latest stable Dart SDK version?
Looking that up… the latest stable is X.Y.Z.
```

Tools are declared to the model the way every BentOS agent declares them, and the body executes them — the same dispatch the `llm` agent-loop proved, now inside a program. The line a chatbot does not cross is the host: **no shell, no filesystem, no mutation of your system.** Agents that act on your machine are a different species.

---

## Devices

`chatbot` uses the same device model as `llm`. The default device is whatever `$BENTOS_LLM_DEVICE` points at, or the one set via `llm config default`.

```sh
chatbot -d anthropic/claude-sonnet-4 "write a haiku about latency"
```

---

## The Session HUD

> [!NOTE]
> **Gap — HUD shape in a terminal.** The SDK separates the conversation UI (clean, user-facing) from the session inspector (rewind, fork, internal state). In a graphical surface this is the "F12 inspector" — open it and you see the machinery; close it and the UI is pure again. In a terminal, what that surface looks like is not yet decided. A `--hud` flag? A parallel pane? A sub-command family? This is an open design question that will resolve when the first real session UI exists.

---

## What `chatbot` is — and is not

`chatbot` **is** the base species every acting agent descends from: text in, text out, remembered — plus the ability to look outward at the world. It **is not** an agent over your system. It does not run shell commands, read or write your files, or act on the host. The boundary is **inward vs outward**: it may query the world; it may not touch your machine.
