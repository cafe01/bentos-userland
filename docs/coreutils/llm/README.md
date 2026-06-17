# `llm` — language-model inference from your shell

```sh
llm "explain the Matter protocol in one sentence"
```

`llm` is the ~~HumanOS~~  BentOS coreutil for talking to a language model. It is the **consumable face of the ChatInference subsystem** ([`chat-inference-dart`](../../../chat-inference-dart)) — nothing more. It opens a **device** — `/dev/llm/<vendor>/<model>` — and its `stdout` *is* the `Stream<ChatEvent>` that device produces, verbatim. `llm` is to the device what `cat` is to `read()`: a faithful, inert projection, oblivious to which company answered.

It holds no API keys and knows no vendors. Provider, credentials, and wire protocol all live in the **driver** behind the device, where the OS manages them once for every program. Swap the device, swap the model — the tool never changes.

> [!IMPORTANT]
> **The honest output is the event stream — `llm` never folds.** The device emits a stream of `ChatEvent`s (typed `text_start`/`text_delta`/…/`complete` frames); `llm` passes them through. It does **not** assemble them into a `ChatMessage` — that is a *reduce* over the stream, and it lives downstream (`chat-data fold`), composed via pipe. This is the law of the family: the device's raw output is the raw output; sugar above it is either an explicit echo-class helper (`--echo-input`) or a separate composable block. `llm` never fuses a transformer into itself, and never invents plumbing the shell already does.

> [!TIP]
> `llm` has two registers, same tool, same device — the flags pick the projection of the stream. **Casual**: `llm "…"` and `llm chat` — text out, the answer streaming to your terminal. **Scriptable**: `… | llm --output-format jsonl` — the structured `ChatEvent` stream, one frame per line, a Unix filter you compose a turn-loop out of.





---

## Quick start

```sh
# Single-shot — streams to your terminal as the model generates.
llm "write a haiku about file descriptors"

# Pick a device explicitly (vendor/model).
llm -d anthropic/claude-sonnet-4 "summarize this commit message"

# Give it a system prompt.
llm -s "You are a terse senior engineer." "is a UUID a good primary key?"

# It's a Unix filter — pipe in, redirect out.
git diff | llm -s "Write a conventional commit message for this diff." > msg.txt

# Hold a throwaway conversation.
llm chat
```

---

## The casual register

### `llm <prompt>` — single-shot (default)

Sends one prompt, streams the answer to `stdout` as plain text, exits. This is what you get with no subcommand. The prompt comes from the argument, or from `stdin` when you pipe:

```sh
llm "what time is it in Tokyo right now, roughly?"
echo "translate to French: good morning" | llm
llm < prompt.txt
```

The answer goes to `stdout`, so ordinary shell plumbing works — `> file` to save, `| pbcopy` to grab, `| less` to page. Streaming still matters when redirected: you watch the answer form, and the redirect captures all of it. In this register the event stream is projected to plain text (text and thinking deltas as UTF-8); non-text blocks are dropped — lossy by design, the `cat`-compatible view.

| Flag | Meaning |
|---|---|
| `-d, --device <vendor/model>` | The device to open. Overrides `$BENTOS_LLM_DEVICE` and the configured default. Accepts an alias (see `config`). |
| `-s, --system <text>` | A system prompt. Repeatable — segments join in order. |
| `-t, --max-tokens <n>` | Cap the generated length. |
| `--temperature <0.0–1.0>` | Sampling temperature. |
| `-v, --verbose` | Print metadata (model · stop reason · token usage) to `stderr` after the answer. |

### `llm chat` — interactive conversation

Opens a throwaway REPL. Each line is a turn; the reply streams back. Context is held **in memory** and grows as you talk, so the model remembers earlier turns in the session.

```
$ llm chat
> my name is Cafe
Nice to meet you, Cafe.
> what's my name?
Your name is Cafe.
> /exit
```

`/exit` or `Ctrl-D` ends the session. Nothing is written to disk — when the process exits, the conversation is gone. `llm` keeps no history; HumanOS does not persist your sessions behind your back. (Persistent, forkable conversation is `chat` over `tx`, a different coreutil — `llm chat` is the inert, in-memory convenience.) `chat` accepts the same `-d` / `-s` flags as the single-shot form.

---

## The scriptable register

The casual register projects the stream to plain text. The scriptable register exposes the structured stream — the device's real output — plus the rest of its I/O config (`ChatIOConfig`, the device's `termios`) as flags, so a turn becomes a composable shell job.

| Flag | `ChatIOConfig` field | Meaning |
|---|---|---|
| `--input-format <text\|typed>` | `inputFormat` | `text` (default): stdin/arg is one user prompt. `typed`: stdin is a conversation — one `ChatMessage` frame per record. |
| `--output-format <text\|typed>` | `outputFormat` | `text` (default): the stream projected to plain text. `typed`: the raw `ChatEvent` stream, one frame per record. |
| `--input-encoding <protobuf\|jsonl>` | — (channel binding) | Honoured when `--input-format typed`. `protobuf` (default): length-prefix framed binary. `jsonl`: newline-framed proto3-JSON. Ignored under `text` format. |
| `--output-encoding <protobuf\|jsonl>` | — (channel binding) | Honoured when `--output-format typed`. `protobuf` (default): length-prefix framed binary. `jsonl`: newline-framed proto3-JSON. Ignored under `text` format. |
| `--output-mode <streaming\|buffered>` | `streaming` | `streaming` (default): typed triads — live, per-delta events. `buffered`: whole-`Block` events only (still events, no folding). |
| `--echo-input` | — | echo-class helper: re-emit each input message on `stdout`, in the output vocabulary, before the answer — so `stdout` carries the **full turn transcript**. Requires `--input-format typed` and `--output-format typed`. |
| `--function <file.json>` | `functions` | Declare a callable function (JSON schema). Repeatable. Requires `--output-format typed`. |
| `--function-choice <auto\|none\|name>` | `functionChoice` | Constrain whether/which function the model may call. |

> [!NOTE]
> **`--output-format jsonl` emits events, not a message.** You get the wire of [chatinference-subsystem.md](../../../hq/workshop/bentos/chatinference-subsystem.md) — `{"type":"text_delta",…}` … `{"type":"complete",…}`, one per line. A consumer that matches only `block` and `complete` works with or without `--stream`; the triads are the extra capability streaming switches on. To collapse the stream into the assembled `ChatMessage`, fold it downstream: `… | chat-data fold`.

### One turn as a filter

The conversation lives in a JSONL file — one `ChatMessage` per line, the transaction-log form. A turn is *fetch the history, run the model, fold the reply, append it*:

```sh
cat messages.jsonl | llm --input-format typed --input-encoding jsonl \
  --output-format typed --output-encoding jsonl \
  | chat-data fold >> messages.jsonl
#   └ fetch          └ run the turn (event stream out)   └ fold to a message   └ store (append = writeback)
```

The fold is explicit and composable — and because the events flow through a pipe, you can tee them to a live view at the same time:

```sh
cat messages.jsonl | llm --input-format typed --input-encoding jsonl \
  --output-format typed --output-encoding jsonl \
  | tee >(chat-render) | chat-data fold >> messages.jsonl
#   render the turn live AND fold it to the record — one stream, the shell tees it.
```

That is the paradigm in one line: the device streams once; the shell sends it to the human and to the record. No plumbing invented.

> [!NOTE]
> This naive append grows the conversation unbounded — the context window treated as an ever-growing list. That is the floor we start from on purpose. Managing the window as a finite resource is a layer built *above* `llm`, not inside it.

### Tools as a shell loop

Function calling needs no agent runtime — it is a `while` loop over `llm`. The model emits a `FunctionCallContent`; a runner executes it, appends the result as a message, and the loop runs `llm` again:

```sh
while true; do
  cat messages.jsonl | llm --input-format typed --input-encoding jsonl \
    --output-format typed --output-encoding jsonl \
    --function weather.json | chat-data fold >> messages.jsonl
  # if the last message is a function call → execute it, append the result, continue
  # else → done
done
```

"Chatbot + tools" is this loop and nothing more. `llm` stays a single-turn filter emitting events; the agency lives in the shell around it.

---

## Choosing a device

A device is `<vendor>/<model>` (the `/dev/llm/` prefix is implied). `llm` resolves which to open, in order:

1. The `-d, --device` flag — including a configured alias.
2. The `$BENTOS_LLM_DEVICE` environment variable.
3. The configured default (`llm config default …`).

If none is set, `llm` says so and shows how to set a default.

### `llm config` — defaults and aliases

The one piece of convenience state: which device to use without `-d`, and short names for the devices you reach for often.

```sh
llm config default anthropic/claude-sonnet-4   # bare `llm "..."` now just works
llm config alias sonnet anthropic/claude-sonnet-4
llm -d sonnet "now i can reach it by a short name"
llm config                                      # show current configuration
```

No key management here — keys belong to the driver.

### `llm models` — list available models

```sh
$ llm models
/dev/llm/anthropic/claude-sonnet-4
/dev/llm/openai/gpt-4o-mini
```

> [!NOTE]
> `llm models` is a stopgap. The right way to enumerate models is `ls /dev/llm/`, because models *are* device files. Until the kernel can list its device namespace, `llm models` reports the devices it knows directly — and later becomes a thin wrapper over `ls`, or disappears.

---

## Errors

`llm` reports failures as the OS sees them. If a device's driver has no credential, opening it fails with a permission error — like opening a file you lack rights to:

```sh
$ llm "hello"
llm: BentosException(eacces) in open: /dev/llm/openai/gpt-4o-mini
```

The fix is to give the *driver* its credential (an env var it reads, e.g. `OPENAI_API_KEY`), not to teach `llm` about keys. `llm` never learns why a device refused it — only that it did.

---

## What `llm` is and is not

It is the `cat` of inference: a thin, inert consumer of an OS primitive, oblivious to which company answered, emitting the device's event stream unchanged. It is **not** an SDK, a provider client, a key manager, a session store, or a stream transformer. The intelligence lives in the device layer and the substrate; folding, rendering, persisting, and accounting are *other* coreutils. `llm` projects the device onto the shell, and stops there.

## Status

| Surface | State |
|---|---|
| `llm <prompt>` · `llm chat` · `llm models` · `llm config` (casual register) | ✅ shipped |
| `--output-format typed` emitting the **event stream** (not a folded message) | ✅ shipped (t-304) |
| `--echo-input` (full-transcript echo) | build target |
| Function calling (`--function` / `--function-choice`) | build target |

The substrate already supports streaming-vs-whole-block, structured conversation, and function calling. The scriptable register is the work of exposing that surface *faithfully* — emitting the raw event stream and letting the shell compose the rest. It adds flags; it does not change the casual register, and it never folds.
