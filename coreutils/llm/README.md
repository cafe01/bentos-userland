# `llm` — talk to a language model from your shell

```sh
llm "explain the Matter protocol in one sentence"
```

`llm` is the HumanOS coreutil for language-model inference. You give it a prompt; it streams back the answer. That is the whole tool — and the whole point.

Under the hood it does not know OpenAI from Anthropic, and it holds no API keys. It opens a **device** — `/dev/llm/<vendor>/<model>` — and reads the answer as it streams, the same way `cat` opens a file and reads bytes. The provider, the credentials, the wire protocol all live in the **driver** behind that device, where the operating system can manage them once for every program. `llm` is a thin, inert consumer of an OS primitive. Swap the device, swap the model — the tool never changes.

---

## Quick start

```sh
# Single-shot — streams to your terminal as the model generates.
llm "write a haiku about file descriptors"

# Pick a device explicitly (vendor/model).
llm -d anthropic/claude-sonnet-4 "summarize this commit message"

# Give it a system prompt.
llm -s "You are a terse senior engineer." "is a UUID a good primary key?"

# Pipe input in; redirect output out. It's just a Unix filter.
git diff | llm -s "Write a conventional commit message for this diff." > msg.txt

# Hold a conversation.
llm chat
```

---

## Commands

### `llm <prompt>` — single-shot (default)

Sends one prompt, streams the answer to `stdout`, exits. This is what you get when you invoke `llm` with no subcommand.

The prompt can come from the argument, or from `stdin` when you pipe:

```sh
llm "what time is it in Tokyo right now, roughly?"
echo "translate to French: good morning" | llm
llm < prompt.txt
```

Because the answer goes to `stdout`, ordinary shell plumbing works — `> file` to save it, `| pbcopy` to grab it, `| less` to page it. Streaming still matters even when redirected: you see the answer form in real time, and the redirect captures the whole of it.

| Flag | Meaning |
|---|---|
| `-d, --device <vendor/model>` | The device to open. Overrides `$BENTOS_LLM_DEVICE` and the configured default. Accepts an alias (see `config`). |
| `-s, --system <text>` | A system prompt. Repeatable — multiple `-s` segments are joined in order. |
| `-t, --max-tokens <n>` | Cap the generated length. |
| `--temperature <0.0–1.0>` | Sampling temperature. |
| `-v, --verbose` | Print metadata (model · stop reason · token usage) to `stderr` after the answer. |

### `llm chat` — interactive conversation

Opens a REPL. Each line you type is a turn; the model's reply streams back. The conversation context is kept **in memory** and grows as you talk, so the model remembers what you said earlier in the session.

```
$ llm chat
> my name is Cafe
Nice to meet you, Cafe.
> what's my name?
Your name is Cafe.
> /exit
```

`/exit` or `Ctrl-D` ends the session. Nothing is written to disk — when the process exits, the conversation is gone. `llm` does not keep history; HumanOS does not persist your sessions behind your back.

`chat` accepts the same `-d` / `-s` flags as the single-shot form.

### `llm models` — list available models

Lists the model devices you can talk to.

```sh
$ llm models
/dev/llm/anthropic/claude-sonnet-4
/dev/llm/openai/gpt-4o-mini
```

> **Note** — `llm models` is a stopgap. The right way to enumerate models is `ls /dev/llm/`, because models *are* device files. The kernel cannot yet list its device namespace, so `llm models` reports the devices it knows about directly. When the kernel grows directory listing over `/dev/llm/`, this command becomes a thin wrapper over `ls` — or disappears. It exists today so the gap is never silently forgotten.

### `llm config` — defaults and aliases

The one piece of convenience state: which device to use when you don't pass `-d`, and short names for the devices you reach for often.

```sh
# Set the default device, so bare `llm "..."` just works.
llm config default anthropic/claude-sonnet-4

# Alias a long device path to a short name.
llm config alias sonnet anthropic/claude-sonnet-4
llm -d sonnet "now i can reach it by a short name"

# Show the current configuration.
llm config
```

There is no key management here — keys belong to the driver, not to you and not to this tool.

---

## Choosing a device

A device is `<vendor>/<model>` (the `/dev/llm/` prefix is implied). `llm` resolves which one to open in this order:

1. The `-d, --device` flag — including a configured alias.
2. The `$BENTOS_LLM_DEVICE` environment variable.
3. The configured default device (`llm config default …`).

If none of these is set, `llm` tells you so and shows how to set a default.

---

## Errors

`llm` reports failures as the operating system sees them. If the driver behind a device has no credential, opening the device fails with a permission error — exactly like opening a file you lack rights to:

```sh
$ llm "hello"
llm: BentosException(eacces) in open: /dev/llm/openai/gpt-4o-mini
```

The fix is to give the *driver* its credential (an environment variable it reads, e.g. `OPENAI_API_KEY`), not to teach `llm` about keys. `llm` never learns why a device refused it — only that it did.

---

## What `llm` is not

It is not an SDK, not a provider client, not a key manager, and not a session store. It is a coreutil: small, composable, and oblivious to which company answered. The intelligence lives in the device layer; `llm` is the `cat` of inference.

Function calling, tool use, and structured output are supported by the underlying subsystem but are not surfaced by this coreutil in v0.1 — they are a deliberate later product question, not an oversight.
