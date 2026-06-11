# `chat-render` — the turn, rendered

```sh
llm … | chat-render
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
| `SignatureDelta` | verification artifact — **never surfaced** (opaque, round-trip data, not for the human — no flag) |
| `FunctionCallStart` / `FunctionArgsDelta` / `FunctionCallStop` | a function call — a call card (name known at open; args assemble) |
| `Block` (whole) | a non-fragmenting block — rendered whole, by its `ChatContent` kind |
| `Complete` | turn boundary — a minimal end-of-turn marker (token usage is `stats`' job, never `chat-render`'s) |

> [!NOTE]
> **Speech streams; arguments do not.** Text and thinking are consumable per-delta — the incremental print *is* the UX. Function-call argument deltas are transport artifacts, inconsumable piecemeal — nobody renders half a JSON argument (chatinference §ChatEvent, "semantic asymmetry"). The renderer shows the call is *forming* but commits to the call only at `FunctionCallStop`. The minimal per-block state it holds — which block is open, the args accumulating for display — is exactly what *rendering* needs, and never a fold into a `ChatMessage`.

> [!NOTE]
> **One vocabulary, both modes.** A consumer that matches only `Block` and `Complete` works whether streaming is on or off (chatinference §"One vocabulary, both modes"). `chat-render` renders the typed triads when they are present (live typing) and whole `Block`s when they are not — the same renderer, no second code path. Streaming is a capability switched on, not a different schema.

---

## CLI

`chat-render` has **no subcommands** — it is a pure filter, one mode, one contract. Flags tune the projection; the pipeline is the composition.

```
Usage: llm … | chat-render [options]
       chat-render [options] < fixture.jsonl

A pure filter: reads a ChatEvent JSONL stream on stdin and renders it to
human-readable styled text on stdout. SignatureDelta is always silently
dropped (opaque by contract). Everything else is dispatched by event type.

Content:
  --[no-]thinking      show/hide thinking blocks
                       (default: on — thinking is rendered dim/italic)
  --[no-]calls         show/hide function-call cards
                       (default: on)

Format:
  --[no-]ansi          ANSI color and styling
                       (default: auto — on if stdout is a TTY, off if piped)
  --width <n>          max columns for call-card and block layout
                       (default: terminal width if TTY, 0 if piped; 0 = no limit)
  --compact            condensed output: suppresses the turn-boundary marker
                       and reduces call-card chrome; does not affect --ansi

Turn boundary:
  --[no-]boundary      emit a turn-end marker at Complete
                       (default: auto — on if stdout is a TTY, off if piped)

Other:
  -h, --help           print this help
```

### Why no subcommands

`chat-render` is a map: one event stream in, one rendered stream out. Subcommands imply distinct operating modes, but the only variation here is *what to project* (flags) and *how to style it* (flags). Adding a subcommand would be adding a second pipeline stage inside the filter — the same anti-pattern the law of the family explicitly prohibits. The shell is the REPL; composition is via pipe.

### Options in detail

**`--[no-]thinking`** (default: on)

Thinking blocks (`ThinkingStart/Delta/Stop`) are rendered by default, styled distinctly from speech (dim + italic, or equivalent). Pass `--no-thinking` to suppress them entirely — useful when you want to read the answer without the reasoning trace, or when the thinking block is very long and you are in a narrow context.

**`--[no-]calls`** (default: on)

Function-call cards are rendered by default. Pass `--no-calls` to suppress them — the call still happened; you just don't see it. Useful in non-interactive pipelines where function call noise is irrelevant.

**`--[no-]ansi`** (default: auto)

When stdout is a TTY, ANSI color and styling are on. When piped, they are off. Pass `--ansi` to force styling even in a pipe (e.g., when the downstream knows how to handle it — `| less -R`). Pass `--no-ansi` to force plain text even in a TTY (scripts, CI, accessibility). The auto-detection uses `stdout.hasTerminal`.

**`--width <n>`** (default: terminal width if TTY, 0 if piped; 0 = no limit)

Controls the column budget for call-card layout and block formatting. Has no effect on streaming text deltas (the terminal wraps those). When stdout is a TTY the default is the current terminal width; when piped the default is `0` (no limit) — the downstream has not asked for wrapping, and imposing it would be inventing plumbing. Same family of reasoning as `--ansi` and `--boundary` auto-detection.

**`--compact`**

Condensed mode: suppresses the turn-boundary marker at `Complete` and reduces call-card chrome (e.g., no box-drawing, no labels). Text and thinking still render at full fidelity. Implied by nothing — it is an explicit opt-in. Does not imply `--no-ansi`.

**`--[no-]boundary`** (default: auto)

At `Complete`, `chat-render` emits a minimal turn-boundary marker (a visual separator, the stop reason — **not** token counts; those belong to `stats`). When stdout is a TTY the boundary is on by default; when piped it is off (a separator in a pipe is noise). Override with `--boundary` to force it in a pipe, or `--no-boundary` to suppress it in a TTY.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | rendered — stream processed (complete turn *or* partial/cancelled turn) |
| `1` | data error — a JSONL line could not be decoded as a `ChatEvent` |
| `2` | usage error — invalid flag or option |

A cancelled turn (SIGINT, broken pipe, producer killed mid-stream) has no `Complete` event and exits `0` — the renderer does not moralize about completeness. In this paradigm a turn is a foreground job and cancellation is a normal outcome, not a failure.

**Stdin empty**: exits `0`, no output. An empty stream is a valid no-op.

**Malformed line**: logs the line number and error to stderr, exits `1`. Does not attempt to continue — a line that cannot be decoded as a `ChatEvent` is corrupt input (distinguishable from a valid-but-empty stream), and silently skipping events could produce a misleading rendering (an open block with no close, a call card that never commits).

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
llm … | chat-render                        # render a raw device stream
chat "…" | chat-render                     # render a turn
cat fixture.jsonl | chat-render            # render a synthetic fixture — dev loop, no inference
cat fixture.jsonl | chat-render --no-ansi  # plain text, for a script or CI check
llm … | tee >(chat-render) | chat-data fold >> session.jsonl
#                                          # render live AND fold to record — one stream, shell tees
```

The unit is the same in every case: a `Stream<ChatEvent>` on stdin. Where it came from — a live device, a stored log replayed, a hand-scripted fixture — is another layer's concern.

---

## Open seams (design in progress)

- **Output visual design.** How each renderer actually looks — role colors, thinking style, call-card layout, the exact boundary marker shape. Each renderer is a TUI widget; their visual contracts are a separate UI design document.
- **The stored-log boundary.** Replaying a persisted turn (`tx cat | … | chat-render`) needs whatever decodes `tx`'s opaque bytes back into events. That decode is a later pipeline stage; `tx` is deliberately out of this design for now.
- **Live renderer vs post-hoc.** Whether `chat` renders through `chat-render` in-process or pipes to it. Lean: the *same* projection, shared — one renderer, two call sites.

---

## Authority

- The event / message ontology (the spine this maps over) — [`hq/workshop/bentos/chatinference-subsystem.md`](../../../hq/workshop/bentos/chatinference-subsystem.md)
- The chat coreutils category + the projection family — [`../chat.md`](../chat.md)
- The paradigm — the shell is the REPL, the turn is a job — [`../../../hq/workshop/humanos/userland/the-userland-paradigm.md`](../../../hq/workshop/humanos/userland/the-userland-paradigm.md)
- General coreutil principles + the loop-ownership test — [`../README.md`](../README.md)
