# `chat-render` — UI design

This document defines the **visual contract** of each renderer in `chat-render`: what every event type actually looks like on the terminal. The [README](./README.md) owns the *CLI* — the flags, the exit codes, the orthogonality. This owns the *form* — glyphs, styling, degradation, the shape of each widget.

> The division mirrors a traditional TUI: the README is the component's public API; this is its rendered appearance. Each renderer is a **widget** — a small, self-contained UI component keyed to one `ChatEvent` kind.

---

## Principles

Three taste laws govern every widget below. They are not stylistic preferences; each one falls out of the substrate.

**1. ANSI is an enhancement layer — never the semantic carrier.**
Color and styling (dim, italic, hue) make a rendering *pleasant*; they must never be the *only* thing that distinguishes one kind of content from another. A user piping through `--no-ansi` (scripts, CI, accessibility, `less` without `-R`) must lose beauty, never **meaning**. Therefore every semantic distinction — *this is thinking, not speech*; *this is a tool call* — is carried by a **textual marker** that survives the loss of ANSI. Styling then reinforces what the marker already says.

**2. Markers are short and left-anchored — never full-width chrome.**
This is the `--width` law (README, "Prose is never hard-wrapped") applied to decoration. A full-width rule (`─────…` spanning the terminal) or a box drawn to the current column count is frozen at render-time width; on resize it strands exactly as hard-wrapped prose would. So every marker is a **short, fixed, left-anchored glyph** (`┌ thinking`, `→ name`) whose meaning is independent of terminal width. Box-drawing that spans width is deferred and opt-in (see Open seams), because it cannot reflow.

**3. Streaming fidelity constrains layout.**
The renderer prints as the stream flows; it cannot know the end at the beginning. So no widget may depend on knowing its final size: no right-alignment, no centering, no box that needs the closing dimension, no "N tokens" tallied before `Complete`. What streams, streams; what can only be known whole (a tool call's assembled arguments) commits at its `Stop`. The incremental print *is* the UX, never a buffer-then-format.

---

## The semantic palette

Concrete colors are deferred to a theme pass (see Open seams). What is fixed now is the **role assignment** — the meaning each style carries. A theme maps these roles to actual SGR codes; the roles themselves are the contract.

| Role | Meaning | Default style (ANSI) | Marker (survives `--no-ansi`) |
|---|---|---|---|
| `speech` | assistant's answer — the primary content | default foreground, undimmed | none — speech is the unmarked baseline |
| `thinking` | reasoning trace | dim + italic | `┌ thinking` … `└` |
| `call` | a function/tool call the model requested | name in an accent hue, args dim | `→ name …` |
| `boundary` | turn-end marker | dim | `─` / `→` / `⚠` per stop reason |
| `notice` | a stop reason that demands attention (truncation, filter) | warning hue (e.g. yellow) | `⚠ …` |

Speech is deliberately the **unmarked default**: the answer should read clean, with no prefix, no gutter, no role label. Everything else earns a marker by being *not the answer*.

---

## Rendering substrate

The widgets below are defined against **semantic roles**, never against a specific library. Two pub.dev packages provide the ANSI backend; our own widget model sits above them and stays backend-pluggable.

**Styling — [`ansicolor`](https://pub.dev/packages/ansicolor).** The SGR layer: maps each `palette` role to color / dim / bold. Mature and verified (Dart-team-adjacent, ~2M downloads). Its TTY-detection and global `color_disabled` flag map directly onto `--[no-]ansi` (README). *Build-time check:* confirm it emits dim (SGR 2) and italic (SGR 3) — the `thinking` and `boundary` roles need them; if absent, a 5-line SGR helper or `tint` supplements. No hand-written escape codes anywhere.

**Glyphs — [`term_glyph`](https://pub.dev/packages/term_glyph).** Maintained by the Dart team (tools.dart.dev, ~6.7M downloads). Every marker glyph (`┌`, `└`, `→`, `⚠`, `─`, `┊`) comes from `term_glyph`, which guarantees a **same-width ASCII fallback** for each via the global `glyph.ascii` flag. This is the **second degradation axis** — Unicode ↔ ASCII — and it is *independent* of the styling axis. A terminal or locale without UTF-8 still reads the markers (`+ thinking`, `->`, `!`); the same-width guarantee keeps columns aligned.

**Two independent degradation axes.** Every widget must keep its meaning when *either or both* are stripped:

| Axis | Enhanced | Degraded | Control | Auto-detect from |
|---|---|---|---|---|
| styling | ANSI color/dim/italic | plain text | `--[no-]ansi` | `stdout.hasTerminal` (TTY) |
| glyphs | Unicode markers | ASCII markers | `--[no-]unicode` *(new — add to README at impl)* | locale (`LANG`/`LC_CTYPE` UTF-8) |

The **legibility floor** is `--no-ansi --ascii`: plain text, ASCII markers, full semantics. Everything above the floor is enhancement. *(Note: `--[no-]unicode` is a natural sibling of `--[no-]ansi`; it is not yet in the README CLI block — add it when implementing, auto-detected from locale, default Unicode on a UTF-8 locale.)*

**The widget model is ours, backend-pluggable.** `ansicolor` + `term_glyph` are the *ANSI backend*. The widget definitions (speech / thinking / call / boundary) route through a thin backend interface (role → style, name → glyph) — never calling the libraries inline. A later **Flutter backend** renders the same widget ontology to GUI (the HumanOS `Chat.app` / `LLM.app` bridge). The widget concept is the durable asset; the backend is swappable.

**Not `pixel_prompt`.** `chat-render` is a streaming *filter*, not a stateful TUI — a full TUI framework would reimport the app-owns-screen model the paradigm rejects. The one redraw (call *forming → committed*) is a trivial single-line `\r` + erase. (A real TUI framework earns its price in the *stateful, GUI-dual* coreutils — a separate front; see the TUI⇄GUI duality thesis.)

---

## The widget catalog

One section per renderer. Each shows the streaming behavior, the ANSI form, and the `--no-ansi` form.

### Speech — `TextStart` / `TextDelta` / `TextStop`

The baseline. Deltas print incrementally and raw — no prefix, no wrapping, default foreground. The terminal owns line-breaking (Principle 2 / the `--width` law). `TextStart` and `TextStop` produce **no visible mark** of their own; they only open and close the block the deltas fill.

```
The quick brown fox jumps over the lazy dog.
```

Identical with or without ANSI — speech carries no styling to lose. This is intentional: the answer is substrate, not decoration.

### Thinking — `ThinkingStart` / `ThinkingDelta` / `ThinkingStop`

Reasoning, set apart from the answer. A short lead-in marker at `Start`, the body streaming dim + italic, a short close at `Stop`. The markers are the semantic carrier; the styling is the reinforcement.

ANSI:
```
┌ thinking
  Let me reason about this step by step. First, I consider the constraints.
└
```
*(the `┌ thinking` / `└` rendered dim; the body dim + italic)*

`--no-ansi`:
```
┌ thinking
  Let me reason about this step by step. First, I consider the constraints.
└
```
*(same markers, plain body — the distinction survives entirely in the `┌ thinking` / `└` frame)*

The body is indented two columns as a soft visual offset. The indent is applied at `Start`/after each newline the model itself emits — never as a hard wrap of flowing text. Suppressed entirely by `--no-thinking`.

### Function call — `FunctionCallStart` / `FunctionArgsDelta` / `FunctionCallStop`

A call the model requested. The name is known at `Start`; the arguments assemble across `FunctionArgsDelta` and are **inconsumable piecemeal** (nobody reads half a JSON argument — chatinference §"semantic asymmetry"). So the widget shows the call is *forming* at `Start` and *commits* the assembled arguments at `Stop`.

On a TTY, forming-then-committed reuses one line (carriage return, no scrollback churn):

At `Start`:
```
→ get_weather …
```
At `Stop` (the `…` resolves to the assembled, single-line raw JSON):
```
→ get_weather {"city":"São Paulo","unit":"celsius"}
```

In a pipe or `--no-ansi`, the forming step is dropped (a redraw is meaningless off-TTY) — only the committed line is emitted, once, at `Stop`. The `→` glyph and the name carry the semantics; the accent hue and dim args are the ANSI reinforcement. Arguments stay **one line, raw** — never pretty-printed across newlines (Principle 2: multi-line JSON would freeze at render width). The terminal soft-wraps long argument strings. Suppressed entirely by `--no-calls`.

### Whole block (non-streaming) — `Block`

When streaming is off, a content block arrives whole as a single `Block` event rather than a `Start/Delta/Stop` triad. **It renders through the same widget**, by its `ChatContent` kind:

- `Block(TextContent)` → the speech widget, printed whole.
- `Block(FunctionCallContent)` → the call widget, committed in one step (no forming phase — there was no stream).
- `Block(ThinkingContent)` → the thinking widget, printed whole.

One widget set, two entry paths — the README's "one vocabulary, both modes" made visual. There is no second appearance for non-streaming content; the only difference the user sees is that it arrives all at once.

### Turn boundary — `Complete`

The end of the turn. Minimal by design — token usage is **never** shown here (that is `stats`, the ATP-meter). What the boundary *does* surface is the **stop reason**, because some stop reasons change the meaning of everything above them. On by default on a TTY, off in a pipe (a separator is noise downstream); overridable with `--[no-]boundary`.

| `stop_reason` | Marker | Why |
|---|---|---|
| `end_turn` | a blank line (no glyph) | normal completion needs no announcement |
| `function_call` | `→ (awaiting tool result)` (dim) | the turn yielded to a tool; the loop continues — the answer is *not* final |
| `max_tokens` | `⚠ truncated — max_tokens` (notice) | the content above is **incomplete**; the user must know |
| `stop_sequence` | `─ (stop sequence)` (dim) | completed, but on a configured stop string — mild signal |
| `content_filter` | `⚠ stopped — content_filter` (notice) | the turn was cut by policy; the content is partial by force |

The two `⚠ notice` cases are the reason the boundary is not purely cosmetic: a truncated or filtered turn *looks* like a finished answer without the marker. Markers carry the meaning; the notice hue reinforces it. `--compact` suppresses the boundary for `end_turn` and `stop_sequence` (the quiet cases) but **keeps** the two `⚠` notices — a warning is never compacted away.

### Signature — `SignatureDelta`

**Never rendered. No flag.** A signature is opaque round-trip verification data, meaningless to a human and not interpretable by design (README, dispatch table). The widget for it is the empty rendering. Exposing a flag would invite interpreting what the system declares uninterpretable.

---

## Degradation matrix

How each widget survives the loss of ANSI (the styling axis). The invariant: **every row keeps its meaning in the plain column.** The glyph axis degrades orthogonally — every marker below is a `term_glyph` with a same-width ASCII fallback (`┌`→`,`, `→`→`>`, `⚠`→`!`, `─`→`-`), so the worst case (`--no-ansi --ascii`) is plain text with ASCII markers and still-intact semantics.

| Widget | ANSI form | `--no-ansi` form | Semantic carrier |
|---|---|---|---|
| speech | plain text | plain text | the text itself |
| thinking | dim italic body, dim frame | plain body, plain frame | `┌ thinking` / `└` |
| call | accent name, dim args, `→` | `→ name {args}` | `→` + name |
| boundary (`end_turn`) | blank line | blank line | (none needed) |
| boundary (`function_call`) | dim `→ (awaiting tool result)` | `→ (awaiting tool result)` | the text |
| boundary (`max_tokens`) | yellow `⚠ truncated — max_tokens` | `⚠ truncated — max_tokens` | `⚠` + text |
| boundary (`content_filter`) | yellow `⚠ stopped — content_filter` | `⚠ stopped — content_filter` | `⚠` + text |
| signature | (nothing) | (nothing) | — |

No row relies on color alone. That is the whole point of the column.

---

## Compact mode (`--compact`)

`--compact` is for density, not for stripping meaning. It collapses **chrome**, never **content or warnings**:

- thinking: keep the body, drop the indent; the `┌ thinking` / `└` frame collapses to a single inline lead `┊ thinking:` (one line, no closing mark).
- call: keep `→ name {args}`; drop any future box-drawing chrome (there is none in the default form, so compact and full coincide today).
- boundary: suppress `end_turn` and `stop_sequence` markers entirely; **keep** `function_call` (the loop signal) and both `⚠` notices (warnings are never compacted).
- speech: unchanged — the answer is never compacted.

`--compact` does **not** imply `--no-ansi` (README): condensed and colored are orthogonal axes.

---

## Worked examples

Rendering the actual fixtures (`coreutils/chat-render/fixtures/`), default TTY + ANSI unless noted.

**`text-simple.jsonl`** →
```
The quick brown fox jumps over the lazy dog.
```
*(then a blank-line boundary for `end_turn`)*

**`thinking-and-text.jsonl`** →
```
┌ thinking
  Let me reason about this step by step. First, I consider the constraints.
└
The answer is 42.
```

**`function-call-single.jsonl`** → (forming step shown then resolved in place; final state:)
```
→ get_weather {"city":"São Paulo","unit":"celsius"}
→ (awaiting tool result)
```
*(the second line is the `function_call` boundary — the turn yielded to the tool)*

**`function-call-single.jsonl` under `--no-ansi --no-boundary`** →
```
→ get_weather {"city":"São Paulo","unit":"celsius"}
```
*(no forming redraw, no boundary, no color — the call line alone, fully legible)*

**`complete-max-tokens.jsonl`** → the content above, then:
```
⚠ truncated — max_tokens
```
*(survives `--compact` and `--no-ansi` — a warning is never dropped)*

---

## Open seams

- **The `--[no-]unicode` flag.** The glyph degradation axis (Rendering substrate) implies a CLI flag that is not yet in the README's CLI block — a sibling of `--[no-]ansi`, auto-detected from the locale (UTF-8 → Unicode), togglable. Add it to the README when implementing.
- **Theme / palette concretization.** The semantic roles are fixed; the SGR codes behind them are not. A theme file (role → color) is the next layer — light/dark/high-contrast variants, 8-color vs 256-color fallback. Deferred to a styling pass.
- **Box-drawing call cards.** A bordered card for tool calls is possible but width-frozen (Principle 2), so it is opt-in future work, not the default. The default call form is a single styled line precisely to stay resize-safe.
- **Forming-step redraw mechanics.** The TTY carriage-return redraw for the call "forming → committed" transition needs a concrete cursor protocol (single-line only, never multi-line, to keep scrollback clean). An implementation detail to pin at build time.
- **Indent vs the prose law.** The two-column thinking indent is a soft offset applied only after model-emitted newlines, never a hard wrap. Confirm in implementation that it never injects `\n` into flowing text.

---

## Authority

- The CLI contract this dresses — [`./README.md`](./README.md)
- The event ontology being rendered — [`hq/workshop/bentos/chatinference-subsystem.md`](../../../hq/workshop/bentos/chatinference-subsystem.md)
- The law of the family — [`../chat.md`](../chat.md)
