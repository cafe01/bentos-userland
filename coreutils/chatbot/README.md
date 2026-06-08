# `chatbot` — a conversation that remembers

```sh
chatbot
```

`chatbot` is the HumanOS conversational agent. You talk; it replies. When you close it, the conversation is still there — resume it tomorrow, same thread, same context, as if you'd never left.

Under the hood it does not hold credentials or know which provider powers it. It opens a device — `/dev/llm/<vendor>/<model>` — and every turn is appended to a **session log** the brain writes at each step. The provider is the driver's concern. The session is yours.

---

## Quick start

```sh
# Start a new conversation.
chatbot

# Resume your last session.
chatbot resume

# Single-shot — an answer without opening a session.
chatbot "what is the capital of Burkina Faso?"
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
> **Gap — long-session strategy.** What happens when a session log grows past the model's context window? Summarization, truncation, or a sliding window — not designed yet. `llm chat` sidesteps this by not persisting; `chatbot` cannot. This is a real frontier.

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

## The Session HUD

> [!NOTE]
> **Gap — HUD shape in a terminal.** The SDK separates the conversation UI (clean, user-facing) from the session inspector (rewind, fork, internal state). In a graphical surface this is the "F12 inspector" — open it and you see the machinery; close it and the UI is pure again. In a terminal, what that surface looks like is not yet decided. A `--hud` flag? A parallel pane? A sub-command family? This is an open design question that will resolve when the first real session UI exists.

---

## Devices

`chatbot` uses the same device model as `llm`. The default device is whatever `$BENTOS_LLM_DEVICE` points at, or the one set via `llm config set default-device`.

```sh
chatbot -d anthropic/claude-sonnet-4 "write a haiku about latency"
```

---

## What `chatbot` is not

`chatbot` does not execute tools. It does not browse the web, run shell commands, or read your files. It is the **base species** — text in, text out, remembered. Agents that act come later. `chatbot` is what they all descend from.
