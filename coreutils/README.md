# coreutils

The HumanOS coreutils — small native programs the agent orchestrates. Single-purpose, agent-facing: invoked, do one thing, terminate. Composable via pipes (IPC) or linked in-process as libraries. This directory **is** the programmatic Agent SDK. Taxonomy authority: `hq/workshop/humanos/userland.md`.

## The thesis: the SDK *is* the coreutils

"Let the SDK emerge from building" has a concrete answer: there is no framework to emerge into. The SDK is this collection of orthogonal coreutils, each usable as an executable (shell composition) and as a linkable library (in-process composition) — coreutils-as-lib, the busybox shape. Building the harness blocks as coreutils **is** the act of shipping the SDK. This holds across every category below, not just chat.

> [!IMPORTANT]
> **SDK vs framework — the test is one question: who owns the loop?**
> A framework owns the `while` and calls your code (inversion of control — LangChain, LangGraph, OpenAI `Runner`, Anthropic `query()`). An SDK gives you blocks and *you* own the `while`. A coreutil reads stdin, transforms, writes stdout, and exits — by construction it can never own your loop. That is why coreutils are genuinely an SDK and cannot drift into a framework by accident. Our shell (the app) always holds the `while`.

> [!NOTE]
> **The dual nature is universal.** Every coreutil is both a standalone program (`tool args | tool`, debuggable, swappable, `tee`-able) and a linkable library (`libtool`) for fusing hot stages into one process. The decomposition is the *contract* boundary; deployment may fuse. CLI and a single linked binary are the same blocks at two fusion levels.

## The categories

Per `userland.md`, coreutils divide by who and what they serve. A category earns a subdirectory only when a second member exists; until then the conceptual grouping stands without the folder.

| Category | Serves | Members | Backing |
|---|---|---|---|
| **Interaction** | agent ↔ human | `ask`, `open` | the host compositor |
| **AI — chat/language** | agent ↔ language model | `llm` + the chat record tools (`chat-render`, `txlog`, `stats`, `filter`) + `websearch` | `/dev/llm/*` · see **`chat.md`** |
| **AI — voice** | agent ↔ speech | `tts`, `stt` | `/dev/tts/*`, `/dev/stt/*` (future) |
| **AI — vision** | agent ↔ image understanding | `vision` | `/dev/vision/*` (future) |
| **AI — generation/embedding** | agent ↔ other modalities | `diffuse`, `embed` | `/dev/diffuse/*`, `/dev/embed/*` (future) |

> [!TIP]
> **HumanOS is AI-native, not LLM-native.** `llm` is as primitive as `cat`; `tts`/`stt` as primitive as `read`/`write`. Every modality is a first-class OS primitive backed by its own device class, composable via pipes: `stt | llm | tts` (voice conversation), `vision | llm` (describe an image), `llm | diffuse` (prompt to image). The coreutil is the thin program that speaks to the device; the agent orchestrates the coreutils.

## A pattern that recurs per modality

Each AI modality produces a **record type** with a JSONL wire (one record per line), and grows a family of operations over that record — a projection (render), a fold (stats), a filter, a structural/session tool. The chat modality is the first to populate this fully; its record is the `ChatMessage` and its family is documented in **`chat.md`**. Future modalities recapitulate the shape with their own record types — the taxonomy is reusable, the record type is not.

## What's here

| Program | Category | Status |
|---|---|---|
| `llm` | chat | shipped — casual + scriptable registers, JSONL, function calling |
| `chatbot` (app) | chat | shipped — REPL + disk sessions + generic tool dispatch (an *app*, not a coreutil — it owns the loop) |
| `websearch` | chat (outward tool) | in progress — multi-engine behind one coreutil |
| `chat-render`, `txlog`, `stats` | chat | planned — see `chat.md` |

## Authority

- Userland taxonomy (the kinds of software, the coreutil categories) — `hq/workshop/humanos/userland.md`
- The chat coreutils category (record, wire, family) — `chat.md`
- Harness design (the A–G block decomposition, our decisions) — `hq/workshop/bentos-agent/design/README.md`
- Userland stdlib surface (the libc layer these compose over) — `../README.md`
