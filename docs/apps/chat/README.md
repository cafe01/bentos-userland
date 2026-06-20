# `chat` — a conversational assistant, anchored to where you are

A prompt, a streamed reply, a sidebar of past conversations, web search, model choice. The category everyone knows — ChatGPT, Claude, Gemini — re-founded on BentOS. The experience is the same; the substrate is the whole difference: your conversations live in *places*, not in an account, and the same product wears two faces — a command-line one and a graphical one — over one shared circuit.

> [!IMPORTANT]
> **`chat` is the app.** Typing `chat` in your terminal *is* the chat application — the loop, the persistence, the rendered transcript, the navigation. There is no separate one-turn `chat` command; a turn is a step *inside* the app, not a coreutil you call. The graphical surface is the same app wearing a different face.

---

## Your conversations live where you are

A traditional chatbot keeps one global store indexed by your account — every conversation in one bucket, the same everywhere, attached to nowhere. `chat` inverts it. Conversation state is **co-located with the place** you are in. Enter a project's place and the assistant there already carries that project's history; leave for another and the context follows your location, not your login.

```sh
cd ~/projects/homfy
chat                       # the conversations you see are homfy's

cd ~/projects/bentos
chat                       # a different place — a different set of conversations
```

This is the differentiator no chat-window competitor can retrofit, because their state was never anchored to a *where*. "Your conversations" is always "your conversations **here**." The grouping that ChatGPT had to invent as a "Project" feature, you get for free — a project *is* a place.

---

## One product, two faces

The command-line `chat` and the graphical `chat` are the **same product, same backend, two frontends**. A frontend is just the input/output face over a shared, byte-for-byte-identical circuit — which input you type into, which surface the reply renders on. Everything between is the same.

- **CLI / TUI** — `chat` in your terminal: a turn is a command, a conversation is a sequence of them, the loop is your shell. You are in your normal shell *and* with the assistant at once.
- **GUI** — the graphical surface: a standing window, a sidebar of conversations, a streamed transcript. The ChatGPT-like experience, rendering the exact same state the CLI reads and writes.

Neither face is the "real" one and the other a port. They are two views of one circuit, and a conversation started in one is continued in the other — because the conversation is on disk, not in either window.

---

## A conversation, as you live it

Nothing is a running process you have to keep alive. The **presence is the disk** — your conversations, their history, always there; the **activity is the turn** — invoked when you send a message, gone when the reply lands. So whether a frontend keeps a window open or is summoned on demand is cosmetic: both are reading and writing the same persistent state.

| you experience… | what it is |
|---|---|
| **where you are** | the place / project whose conversations you see — switching places switches the whole context |
| **whose conversations these are** | you (human or agent) — the assistant talks to you, and your conversations are yours, separate from anyone else's in the same place |
| **a conversation** | a sidebar entry; one conversation is many turns |

---

## Reaching outward — web search

`chat` reaches **outward** to query the world; it never reaches **inward** to your machine. When a question needs current or external information, it searches the web and uses the results. The line it does not cross is the host: no shell, no filesystem, no mutation of your system. An assistant that acts on your machine is a different kind of thing.

---

## What's underneath

`chat` stands on the same OS services any program uses — no vendor SDKs, no keys:

- **inference** is an OS service: `chat` opens a device (`/dev/llm/<vendor>/<model>`), the same any program opens. Provider and credentials are the driver's concern, never the app's.
- **persistence** is [`tx`](../../coreutils/tx/README.md) — git raised into userland — which versions, branches, and time-travels each conversation. The app reads and writes its transcript; `tx` keeps the history.
- **the turn** is a step *inside* the app — a composition of `llm` (cognition), `chat-codec` (the conversation record), and `chat-render` (projection) over `tx`. It is wiring, not a coreutil you call.

> [!NOTE]
> **Built by the beings who use it.** A user of `chat` is anyone the OS models as a user — human *or* agent. An agent (Alfred, John, any being) gets the same product: its own persistent assistant, which it can hand a deep-research dive and receive back only the distillate, sparing its own context. The first users of the app are the beings that build it.

---

## Authority

- The product shape (what we are building and why it is not a chat window) — `hq/workshop/humanos/apps/chat/product.md`
- The engineering doc (the state model, the circuit, the frontends) — `hq/workshop/humanos/apps/chat/engineering.md`
- The frontend model (one backend, many faces) — `hq/workshop/bentos/one-backend-many-frontends.md`
- The storage substrate — [`../../coreutils/tx/README.md`](../../coreutils/tx/README.md)
