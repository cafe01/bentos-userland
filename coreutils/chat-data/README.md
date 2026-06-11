# `chat-data` — the data model as a command

```sh
chat-data msg --user "explain the Matter protocol in one sentence"
```

`chat-data` is the **codec-as-CLI** for the chat subsystem's data model. It constructs, serializes, validates, and inspects the `ChatContent` / `ChatMessage` / `ChatEvent` ontology ([chatinference-subsystem.md](../../../hq/workshop/bentos/chatinference-subsystem.md)) from the shell — the model made scriptable. It is the `printf` of the chat record: a typed constructor that knows the schema, so you never hand-write JSONL again. It invents nothing above the substrate; it is the ontology's honest shell face.

Two directions, because a codec is bidirectional:
- **construct** — flags/args → JSONL frames on stdout.
- **inspect / validate** — JSONL on stdin → fields, or an exit code.

---

## The multitool — one entry per layer of the ontology

`chat-data` is a busybox-style multicall, one subcommand per layer of the content ontology plus the transformers that operate on it:

| Subcommand | Job |
|---|---|
| `chat-data msg` | construct a `ChatMessage` — `--user` / `--system` / `--assistant`, content via repeatable flags |
| `chat-data content` | construct one `ChatContent` block — text, binary, thinking, function-call, function-result, cache-point |
| `chat-data event` | construct `ChatEvent` frames — `text_start`, `text_delta`, `function_call_start`, `block`, `complete`, … |
| `chat-data validate` | read JSONL on stdin, check it against the schema, exit `0` / non-zero |
| `chat-data fold` | the transformer: reduce a `ChatEvent` stream → the assembled `ChatMessage`(s) |

> [!NOTE]
> **`fold` lives here, not in `llm`** (decided with Cafe, S439). The fold (event stream → message) is *data-model tooling*, a reduce over the ontology — not inference. `llm` is the consumable face of the *device*; it must not grow the transformer family inside it. The data model owns its own transformers; `llm` stays the inference face. (Open: a standalone `fold` coreutil could be carved out later if it earns it; for now it is a `chat-data` subcommand.)

---

## Why it exists — two reasons, and the second is the interesting one

### 1. Synthetic, deterministic fixtures

The development substrate for everything that *reads* the record (`chat-render`, `stats`, `validate` itself). Real inference is the wrong fixture source: slow, costly, non-deterministic, and **incomplete** — it is hard to make a live model produce the whole ontology on demand (redacted thinking, binary content, a mid-stream error, multi-block turns, a specific function-call shape). The fixture must cover exactly what the model rarely emits.

```sh
chat-data event text_start text_delta:"Hi" text_stop complete > fixtures.jsonl
chat-data event ... | chat-render          # iterate on the renderer, no live inference, fully deterministic
```

One run of a real model was only ever useful to *exercise the tool and surface bugs* — never as the fixture strategy. Fixtures are 100% synthetic, by `chat-data`.

### 2. Real application composition — the prompt box is a data constructor

`chat-data msg --user "…"` **is the prompt box** — the first `STDIN → JSONL` of a turn's pipeline. The bare `chat`'s prompt box is not special UI; it collapses to:

```sh
chat-data msg --user "…" | chat …
```

The constructor of the data model is a first-class building block of the turn itself, not dev-only scaffolding. The same tool that fabricates a fixture fabricates the real first message of a real turn — because they are the same act: producing a `ChatMessage` on the wire.

---

## Composition

```sh
chat-data msg --user "explain X" | chat …                 # the prompt box → a turn
chat-data event … | chat-render                           # a synthetic render fixture
llm … | chat-data fold >> messages.jsonl                  # fold the event stream to a message, persist
llm … | tee >(chat-render) | chat-data fold >> log.jsonl  # render live AND fold to persist, one stream
llm … | chat-data validate                                # assert a stream conforms to the schema
```

The last two are the paradigm in one line: the event stream flows once, and the shell tees it — to the human (`chat-render`) and to the record (`fold` → append). No plumbing invented; the OS already tees.

---

## Open seams (design in progress)

- **The `event` grammar.** How to express a sequence of frames ergonomically on one command line (positional shorthand vs. repeated flags vs. a small DSL). The argument-shape pass.
- **The inspect direction.** What `chat-data` emits when *reading* a record (field extraction, `jq`-friendly projection) versus leaving raw inspection to `jq` over the JSONL.
- **`msg` multimodal ergonomics.** Constructing a message with mixed content (text + image + function-result) without a clumsy flag soup.

---

## Authority

- The data model this is a codec for — [`hq/workshop/bentos/chatinference-subsystem.md`](../../../hq/workshop/bentos/chatinference-subsystem.md)
- The chat coreutils category + the projection family — [`../chat.md`](../chat.md)
- The renderer that consumes its fixtures — [`../chat-render/README.md`](../chat-render/README.md)
- General coreutil principles + the loop-ownership test — [`../README.md`](../README.md)
