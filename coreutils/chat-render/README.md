# `chat-render` — the turn, rendered

```sh
chat "explain TCP vs UDP in one sentence" | chat-render
```

`chat-render` is the **`map`** of the chat family: it reads the `Stream<ChatEvent>` a turn produces and projects it to a human-readable terminal rendering. It is the first chat coreutil that **reads the content** of the record — `tx` is content-blind, `chat-render` opens the envelope. A pure filter: events in on stdin, styled text out on stdout, then exit. It holds no state on disk, reaches no network, mutates nothing.

---

## It renders events, not the folded message

> [!IMPORTANT]
> **The input is the event stream — the `Stream<ChatEvent>` — not the assembled `ChatMessage`.**

The reason is the streaming UX. Someone who turned streaming on wants to *see* the text being born. Folding the stream into a complete message before rendering would defeat the only reason streaming exists — you would be back to waiting for the whole answer, and the live "typing" would be gone. So `chat-render` consumes the same stream the device emits at `/dev/llm/*` — the very stream a fold transformer would otherwise eat — and renders it *as it flows*.

Being a coreutil of the chat subsystem does **not** bind it to the `ChatMessage`. The `ChatEvent` vocabulary already carries the structure the renderer needs: the typed `Start/Delta/Stop` triads, the whole-`Block`, and `Complete` (see [chatinference-subsystem.md](../../../hq/workshop/bentos/chatinference-subsystem.md) §ChatEvent). From the event *type* alone the renderer knows a text block opened, that a delta is speech to print incrementally, that a block closed, that the turn finished. The `ChatMessage` is one projection of the content ontology; the `ChatEvent` stream is the other; they are isomorphic by construction. `chat-render` maps over the temporal projection — because that is the one that streams.

The wire it reads is the subsystem's structured output, one frame per line (JSON convenience encoding):

```jsonl
{"v":1,"type":"text_start","index":0}
{"v":1,"type":"text_delta","index":0,"text":"Hello"}
{"v":1,"type":"text_stop","index":0}
{"v":1,"type":"complete","metadata":{"model":"…","stop_reason":"end_turn","usage":{…}}}
```

---

## Dispatch by event type

`chat-render` is a table of small renderers keyed by `ChatEvent` type. The event ontology is the contract, and a sub-renderer per kind is the natural shape:

| Event | Rendering |
|---|---|
| `TextStart` / `TextDelta` / `TextStop` | assistant speech — print deltas incrementally (the "typing" effect) |
| `ThinkingStart` / `ThinkingDelta` / `ThinkingStop` | reasoning — styled distinctly (dim/italic), still incremental |
| `SignatureDelta` | verification artifact — not surfaced (opaque, round-trip data, not for the human) |
| `FunctionCallStart` / `FunctionArgsDelta` / `FunctionCallStop` | a function call — a call card (name known at open; args assemble) |
| `Block` (whole) | a non-fragmenting block (binary, redacted thinking, cache point) — rendered whole, by its `ChatContent` kind |
| `Complete` | turn boundary — a minimal end-of-turn marker (see the seam with `stats` below) |

> [!NOTE]
> **Speech streams; arguments do not.** Text and thinking are consumable per-delta — the incremental print *is* the UX. Function-call argument deltas are transport artifacts, inconsumable piecemeal — nobody renders half a JSON argument (chatinference §ChatEvent, "semantic asymmetry"). The renderer shows the call is *forming* but commits to the call only at `FunctionCallStop`. The minimal per-block state it holds — which block is open, the args accumulating for display — is exactly what *rendering* needs, and never a fold into a `ChatMessage`.

> [!NOTE]
> **One vocabulary, both modes.** A consumer that matches only `Block` and `Complete` works whether streaming is on or off (chatinference §"One vocabulary, both modes"). `chat-render` renders the typed triads when they are present (live typing) and whole `Block`s when they are not — the same renderer, no second code path. Streaming is a capability switched on, not a different schema.

---

## What it does not do — orthogonality

`chat-render` is one projection: **content → human view.** Everything adjacent is a different block, composed via pipe, never fused in:

| Concern | Owner |
|---|---|
| fold the event stream into a `ChatMessage` | a transformer (the `fold`), not `chat-render` |
| construct / serialize / validate the data model | `chat-data` (the codec-as-CLI) |
| token spend & counts — the ATP-meter | `stats` (the `reduce`) |
| persist / fork / rewind the history | `tx` (content-blind) |
| produce the events (inference + tool loop) | `llm` / `chat` |

It never mutates, never accounts, never persists, never folds. It reads events and writes a rendering. That orthogonality is the law of the family (the device's honest output is the raw event stream; everything above is an explicit echo-class helper or a separate composable block — never invented plumbing, never a fused use-case).

---

## Composition

```sh
llm … | chat-render                 # render a raw device stream
chat "…" | chat-render              # render a turn (chat's own live output is this same projection)
chat-data … | chat-render          # render a synthetic fixture — the dev loop, no live inference
```

The unit is the same in every case: a `Stream<ChatEvent>` on stdin. Where it came from — a live device, a stored log replayed, a hand-scripted fixture — is another layer's concern.

---

## Open seams (design in progress)

- **The stored-log boundary.** Replaying a persisted turn (`tx cat | … | chat-render`) needs whatever decodes `tx`'s opaque bytes back into events. That decode is a later pipeline stage; `tx` is deliberately out of this design for now.
- **`Complete` and the `stats` line.** How much does `chat-render` show at turn end — a bare separator? the stop reason? — versus leaving token usage entirely to `stats`. Lean: render a minimal turn boundary; the ATP-meter is `stats`' job, kept orthogonal.
- **Theme / palette.** Role colors, thinking style, call-card layout, width handling, TTY-vs-pipe detection (strip ANSI when stdout is not a terminal). Deferred to the styling pass.
- **Live renderer vs post-hoc.** Whether `chat` renders through `chat-render` in-process or pipes to it. Lean: the *same* projection, shared — one renderer, two call sites.

---

## Authority

- The event / message ontology (the spine this maps over) — [`hq/workshop/bentos/chatinference-subsystem.md`](../../../hq/workshop/bentos/chatinference-subsystem.md)
- The chat coreutils category + the projection family — [`../chat.md`](../chat.md)
- The paradigm — the shell is the REPL, the turn is a job — [`../../../hq/workshop/humanos/userland/the-userland-paradigm.md`](../../../hq/workshop/humanos/userland/the-userland-paradigm.md)
- General coreutil principles + the loop-ownership test — [`../README.md`](../README.md)
