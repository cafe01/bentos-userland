# `llm` — language-model inference from your shell

```sh
llm "explain the Matter protocol in one sentence"
```

`llm` is the HumanOS coreutil for talking to a language model. It is the shell face of the **ChatInference subsystem** ([`chat-inference-dart`](../../../chat-inference-dart)): every capability the substrate has — streaming or whole-message, plain text or structured conversation, function calling — `llm` exposes as flags and subcommands. Nothing above the substrate is invented here; `llm` is a faithful CLI projection of `libchat`, the way `cat` is a CLI over `read()`.

It holds no API keys and knows no vendors. It opens a **device** — `/dev/llm/<vendor>/<model>` — and reads the answer as it streams, exactly as `cat` opens a file and reads bytes. Provider, credentials, and wire protocol all live in the **driver** behind that device, where the OS manages them once for every program. Swap the device, swap the model — the tool never changes.

> [!TIP]
> `llm` has two registers. **Casual**: `llm "..."` and `llm chat` — a human or an agent talking to a model, answer streaming to the terminal. **Scriptable**: `cat messages.jsonl | llm --input-format jsonl --output-format jsonl >> messages.jsonl` — a structured Unix filter you compose a turn-loop out of. Same tool, same device; the flags pick the projection.

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

# Hold a conversation.
llm chat
```

---

## The casual register

### `llm <prompt>` — single-shot (default)

Sends one prompt, streams the answer to `stdout`, exits. This is what you get with no subcommand. The prompt comes from the argument, or from `stdin` when you pipe:

```sh
llm "what time is it in Tokyo right now, roughly?"
echo "translate to French: good morning" | llm
llm < prompt.txt
```

The answer goes to `stdout`, so ordinary shell plumbing works — `> file` to save, `| pbcopy` to grab, `| less` to page. Streaming still matters when redirected: you watch the answer form, and the redirect captures all of it.

| Flag | Meaning |
|---|---|
| `-d, --device <vendor/model>` | The device to open. Overrides `$BENTOS_LLM_DEVICE` and the configured default. Accepts an alias (see `config`). |
| `-s, --system <text>` | A system prompt. Repeatable — segments join in order. |
| `-t, --max-tokens <n>` | Cap the generated length. |
| `--temperature <0.0–1.0>` | Sampling temperature. |
| `-v, --verbose` | Print metadata (model · stop reason · token usage) to `stderr` after the answer. |

### `llm chat` — interactive conversation

Opens a REPL. Each line is a turn; the reply streams back. Context is held **in memory** and grows as you talk, so the model remembers earlier turns in the session.

```
$ llm chat
> my name is Cafe
Nice to meet you, Cafe.
> what's my name?
Your name is Cafe.
> /exit
```

`/exit` or `Ctrl-D` ends the session. Nothing is written to disk — when the process exits, the conversation is gone. `llm` keeps no history; HumanOS does not persist your sessions behind your back. `chat` accepts the same `-d` / `-s` flags as the single-shot form.

---

## The scriptable register

The casual register defaults the substrate's I/O to *prompt in, streamed text out*. The scriptable register exposes the rest of the device's I/O config (`ChatIOConfig` — the device's `termios`) as flags, so a turn becomes a composable shell job.

| Flag | `ChatIOConfig` field | Meaning |
|---|---|---|
| `--input-format <text\|jsonl>` | `inputFormat` | `text` (default): stdin/arg is one user prompt. `jsonl`: stdin is a conversation — one `ChatMessage` per line. |
| `--output-format <text\|jsonl>` | `outputFormat` | `text` (default): the answer as plain text. `jsonl`: the assembled assistant `ChatMessage` as one line. |
| `--[no-]stream` | `streaming` | Live token stream vs. whole-message-at-once. Defaults on for `text` output, off for `jsonl`. |
| `--function <file.json>` | `functions` | Declare a callable function (JSON schema). Repeatable. |
| `--function-choice <auto\|none\|name>` | `functionChoice` | Constrain whether/which function the model may call. |

### One turn as a filter

The headline shape. The conversation lives in a JSONL file — one message per line, which is exactly the transaction-log form. A turn is *fetch the history, run the model, append the reply*:

```sh
cat messages.jsonl | llm --input-format jsonl --output-format jsonl >> messages.jsonl
#   └ fetch          └ run the turn                                  └ store (append = writeback)
```

`>>` is an honest append because each line is a self-contained message; the file never has to be rewritten.

> [!NOTE]
> This naive append grows the conversation unbounded — the context window is treated as an ever-growing list. That is the floor we start from on purpose. Managing the window as a finite resource is a layer built *above* `llm`, not inside it.

### Tools as a shell loop

Function calling needs no agent runtime — it is a `while` loop over `llm`. The model emits an assistant message carrying a `FunctionCallContent`; a runner executes it, appends the result as a message, and the loop runs `llm` again:

```sh
while true; do
  cat messages.jsonl | llm --input-format jsonl --output-format jsonl \
    --function weather.json >> messages.jsonl
  # if the last message is a function call → execute it, append the result, continue
  # else → done
done
```

"Chatbot + tools" is this loop and nothing more. `llm` stays a single-turn filter; the agency lives in the shell around it.

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

It is the `cat` of inference: a thin, inert consumer of an OS primitive, oblivious to which company answered. It is **not** an SDK, a provider client, a key manager, or a session store. The intelligence lives in the device layer and the substrate; `llm` projects them onto the shell.

## Status

| Surface | State |
|---|---|
| `llm <prompt>` · `llm chat` · `llm models` · `llm config` (casual register) | ✅ shipped |
| Structured I/O (`--input-format` / `--output-format jsonl`) | build target |
| Function calling (`--function` / `--function-choice`) | build target |

The substrate already supports streaming-vs-message, structured conversation, and function calling. The scriptable register is the work of exposing that surface faithfully through the CLI — it adds flags, it does not change the casual register.
