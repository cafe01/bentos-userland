# `chat-codec` — the chat data model as a command

```sh
chat-codec message --user "explain the Matter protocol in one sentence"
```

`chat-codec` is the **codec-as-CLI** for the chat subsystem's data model — the shell face of `package:chat_inference`. It constructs, transcodes, inspects, and folds the `ChatContent` / `ChatMessage` / `ChatEvent` ontology ([chatinference-subsystem.md](../../../../../hq/workshop/bentos/chatinference-subsystem.md)) from the shell. It invents nothing above the substrate: it is the ontology's honest shell face, the `printf`-and-`iconv` of the chat record in one program.

> [!NOTE]
> **`chat-codec` is the evolution of `chat-data`.** The earlier `chat-data` was the constructor face alone (args → records). Once Encoding and Format became formal axes of the subsystem, the constructor and the transcoder revealed themselves as **one operation** (below), and the data-model tool absorbed both. `chat-codec` is that unified tool; `chat-data` is retired into it.

## The one operation — construct *is* transcode

A codec has a single job: **decode an input into the ontology, re-encode it to the requested wire.** Constructing a synthetic message and transcoding a recorded one are not two jobs — they are the same job with two **input sources**:

| Input source | Reads from | Register |
|---|---|---|
| **arguments** | `argv` (flags) | interactive / synthetic — you author the record on the command line |
| **stream** | `stdin` | pipeline — you re-encode a record that flowed in |

Everything else is identical. The output is always a record in the `(format, encoding)` you asked for. So there is no "constructor mode" versus "transcoder mode" — there is `chat-codec`, gathering its input from argv or stdin, emitting in the requested wire:

```sh
chat-codec message --user "hi" --encoding protobuf       # construct → protobuf
cat msg.jsonl | chat-codec message --encoding protobuf   # transcode jsonl → protobuf
#   same act; only where the message comes from differs.
```

## Three altitudes — the subcommand axis

The content ontology has three altitudes, and `chat-codec` exposes each as a subcommand. A record exists, and is codec-able, at every level — not only at the device's wire pairing:

| Subcommand | Altitude | Constructs / transcodes |
|---|---|---|
| `chat-codec content` | one `ChatContent` block | text · binary · thinking · function-call · function-result · cache-point |
| `chat-codec message` | one `ChatMessage` | `--user` / `--system` / `--assistant`, content via repeatable flags |
| `chat-codec event` | one `ChatEvent` frame | `text-start`, `text-delta`, `function-call-start`, `block`, `complete`, … |

> [!IMPORTANT]
> **The device wire is one altitude-pairing, not the whole codec.** The subsystem's data path is `write(ChatMessage) → read() ChatEvent` — message in, event out. That is *one* combination. `chat-codec` exposes all three altitudes independently, each constructible and transcodable on its own. The wire protocol is a special case of the codec, not its definition.

> [!NOTE]
> **One frame per invocation; the shell sequences.** There is no in-line grammar for a *sequence* of frames — a stream of N events is N invocations, the shell appending (`>> file.jsonl`). One `chat-codec` call produces one record; composition is the shell's job, not a DSL inside the command.

## The I/O matrix — format × encoding

Two orthogonal-but-conditioned axes govern the wire, set per direction (input axes inferred from the source, output axes via `--format` / `--encoding`):

- **Format** — `text` | `typed`. The logical schema: raw UTF-8 versus a typed record.
- **Encoding** — `protobuf` | `jsonl`. The physical wire of a *typed* record: proto3-binary length-prefixed, or proto3-JSON newline-framed.

Every cell of the matrix is a meaningful operation:

| in → out | operation | lossy? |
|---|---|---|
| `text → typed` | **construct** — parse text into a record (role deduction on messages) | no — enriches |
| `typed → typed` (encoding differs) | **transcode** — re-serialize across the wire | no |
| `typed → text` | **render (base)** — flatten a record to legible plaintext | yes — by design |
| `text → text` | **identity** — charset passthrough (UTF-8) | no |

> [!IMPORTANT]
> **Encoding presupposes structure.** The `protobuf` / `jsonl` choice is meaningful *only* when format is `typed` — it serializes and frames **records**, and only typed format has records. Under `text`, the wire is raw UTF-8 with no record boundaries: "encoding" degenerates to the charset (`String → bytes`), not a channel choice. So `--encoding` is **inert under `--format text`** — accepted and ignored, never an error. The matrix is not a free 2×2; `text` collapses the encoding dimension to a point. (Subsystem law: *Encoding presupposes structure*, `chatinference-subsystem.md`.)

## `--format text` *is* the base renderer

Asking for `text` output on a typed input is how you **see what is inside a packet**. A `BinaryContent image/png` flattens to `[image/png, 4.2KB]`; a `RedactedThinkingContent` to its placeholder; a function call to a legible one-liner. It is lossy on purpose — the goal is inspection, not round-trip.

This draws the boundary with [`chat-render`](../chat-render/README.md) cleanly:

| | role |
|---|---|
| `chat-codec … --format text` | the **base** renderer — honest plaintext, `cat`-compatible, "what's in the record" |
| `chat-render` | the **rich** renderer — style, color, markdown, observability, archaeology — stacked *on top* of the base projection |

## Transformers — a family, not a single fold

Beyond the codec, `chat-codec` exposes the subsystem's **stream transformers** as verbs. These are not `decode→encode` — they reshape the event stream. The SDK (`chat_transformers.dart`) ships two today, of different shapes, and the family is open:

| Verb | Shape | Does |
|---|---|---|
| `chat-codec fold` | `Stream<ChatEvent> → ChatMessage` (terminal) | assemble the whole turn into one ordered `ChatMessage`, client-side — the assembled message the stateless device never sends back |
| `chat-codec fold-calls` | `Stream<ChatEvent> → Stream<ChatEvent>` (partial) | collapse each function-call argument run into a single `Block`; speech triads pass through live, so the stream stays consumable without ever touching a partial JSON fragment |

> [!NOTE]
> **Every SDK transformer earns a verb.** `chat-codec` is the shell face of `package:chat_inference`'s codec *and* its transformer family. As the SDK grows a transformer, `chat-codec` grows a verb — the CLI mirrors the library, never reinvents it.

## Why it exists — two reasons, the second the interesting one

### 1. Synthetic, deterministic fixtures

The development substrate for everything that *reads* the record (`chat-render`, `stats`, `validate`). Real inference is the wrong fixture source: slow, costly, non-deterministic, and **incomplete** — it is hard to make a live model emit the whole ontology on demand (redacted thinking, binary content, a mid-stream error, a specific function-call shape). The fixture must cover exactly what the model rarely produces. `chat-codec` fabricates any record, any altitude, deterministically:

```sh
chat-codec event text-start              >> turn.jsonl
chat-codec event text-delta --text "Hi"  >> turn.jsonl
chat-codec event text-stop               >> turn.jsonl
chat-codec event complete --model claude-sonnet --stop end_turn  >> turn.jsonl
chat-codec fold < turn.jsonl             # → the assembled message, no live inference
```

### 2. Real application composition — the prompt box is a data constructor

`chat-codec message --user "…"` **is the prompt box** — the first `argv → JSONL` of a turn's pipeline. The bare prompt box is not special UI; it collapses to a constructor invocation:

```sh
chat-codec message --user "explain X" | llm --input-format typed   # the prompt box → a turn
```

The constructor of the data model is a first-class building block of the turn itself, not dev-only scaffolding. The same tool that fabricates a fixture fabricates the real first message of a real turn — because they are the same act: producing a `ChatMessage` on the wire.

## Composition

```sh
chat-codec message --user "explain X" | llm --input-format typed        # prompt box → turn
chat-codec event text-start text-delta --text "Hi" … | chat-render      # synthetic render fixture
llm --output-format typed … | chat-codec fold >> messages.jsonl         # fold the stream to a message, persist
llm … | tee >(chat-render) | chat-codec fold >> log.jsonl               # render live AND fold to persist, one stream
cat session.jsonl | chat-codec message --encoding protobuf | …          # transcode a log jsonl → protobuf
llm … | chat-codec validate                                             # assert a stream conforms to the schema
```

The fourth line is the paradigm in one stroke: the event stream flows once, the shell tees it — to the human (`chat-render`) and to the record (`fold` → append). No plumbing invented; the OS already tees.

## Place in the bigger picture

`chat-codec` is a **projection of the ChatInference subsystem onto the shell — on the data model and its transformers, never the device.** It imports the ontology from `package:chat_inference` and the subsystem stays the single owner of the types, the wire, and the protocol. What `chat-codec` owns is the userland shell-face the subsystem deliberately does not: constructing records from argv, transcoding them across encodings, projecting them to legible text, folding event streams to messages.

It sits beside `llm` as the other half of the chat coreutil family, and the two never overlap — the loop-ownership and purity tests sort them:

| | `llm` | `chat-codec` |
|---|---|---|
| Speaks to | `/dev/llm` (the device) | the data model (records on the wire) |
| Operation | inference — context in, reaction out | codec + transform — decode→encode, fold |
| Wire posture | **relay** — opens a channel, passes its bytes through verbatim (ioctl surface, never transcodes) | **transform** — constructs and transcodes across altitudes and encodings |

`llm` is the irreducible inference call; `chat-codec` is the data-model tooling around it. Neither owns the loop — the shell (the app) always does.

## Authority

- The data model this is a codec for — [`chatinference-subsystem.md`](../../../../../hq/workshop/bentos/chatinference-subsystem.md)
- The chat coreutils category + the projection family — [`../chat.md`](../chat.md)
- The rich renderer that stacks on the base text projection — [`../chat-render/README.md`](../chat-render/README.md)
- General coreutil principles + the loop-ownership test — [`../README.md`](../README.md)
- The SDK transformer family this mirrors — `lib/chat-inference-dart/lib/src/chat_transformers.dart`
