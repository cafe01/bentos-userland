# `websearch` — web search from your shell and from tools

```sh
websearch "dart 3.9 release notes"
```

`websearch` is the HumanOS coreutil for querying the web. It is a **thin wrapper** over a search engine CLI you already have installed — it delegates every search to that binary, translates the result to a consistent JSONL format, and exits. Nothing is invented above the substrate.

It is also the first **outward tool** an agent can declare. The same binary that answers a shell query is what `chatbot` calls when a question reaches beyond offline knowledge. One contract, two callers.

> [!TIP]
> `websearch` is deliberately minimal. It does not summarize, rank, filter, or score results — it retrieves. Downstream consumers (the model, a pipeline, a human) decide what the results mean. The coreutil's job is to faithfully project the engine's output into a stable, engine-agnostic shape.

---

## Quick start

```sh
# Query DuckDuckGo (default engine, no key required).
websearch "latest stable Dart SDK version"

# Limit to 5 results.
websearch -n 5 "flutter state management comparison"

# Pick the engine explicitly.
websearch --engine ddgr "rust async runtimes"
```

---

## Output — JSONL

Each result is one line of JSON, printed to `stdout`:

```json
{"title":"Get the Dart SDK","url":"https://dart.dev/get-dart","snippet":"This page describes how to download the Dart SDK..."}
```

Fields — exactly three, always present:

| Field | Type | Source | Meaning |
|---|---|---|---|
| `title` | string | engine `title` | Page title |
| `url` | string | engine `url` | Canonical page URL |
| `snippet` | string | engine `abstract` | Excerpt or description |

Field names are **engine-agnostic**: `snippet` instead of `abstract` so the contract does not leak the ddgr vocabulary.

### Piping

Because output is JSONL, standard shell tools compose cleanly:

```sh
# Extract just the URLs.
websearch "flutter packages" | jq -r '.url'

# Feed results into a prompt.
websearch "Dart 3.9 new features" | llm --input-format jsonl "summarise these search results"
```

---

## Options

| Flag | Meaning |
|---|---|
| `-n, --count <N>` | Number of results to return (1–25, default 10). |
| `--engine <name>` | Engine to delegate to. Default: `ddgr`. Supported: `ddgr`. |

### Engines

| Engine | Binary | Key required | Status |
|---|---|---|---|
| `ddgr` | `ddgr` (brew install ddgr) | No | ✅ implemented |
| `googler` | `googler` | No | stub — selector ready, not yet implemented |

The engine is a **delegation detail**, not part of the output contract. Switching engines never changes the JSONL shape.

---

## As a tool — `FunctionDefinition`

This is the JSON schema `chatbot` (or any agent) passes to the model when declaring `websearch` as a callable tool:

```json
{
  "name": "websearch",
  "description": "Search the web and return a list of results. Use when the question requires current or external information not available offline.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "query": {
        "type": "string",
        "description": "The search query."
      },
      "count": {
        "type": "integer",
        "description": "Number of results to return (1–25). Omit to use the default (10).",
        "minimum": 1,
        "maximum": 25
      }
    },
    "required": ["query"]
  }
}
```

The agent invokes the tool by running `websearch <query>` (with `-n <count>` when `count` is provided) and reading `stdout` as JSONL. The dispatch is identical to any other BentOS tool: `Process.start`, stdout captured, one `FunctionResultContent` per call.

A ready-to-use `websearch.json` containing this definition ships alongside the binary.

---

## Errors

`websearch` reports failures to `stderr` and exits non-zero:

| Exit code | Meaning |
|---|---|
| 0 | Results written to `stdout`. |
| 1 | Engine binary not found. Install it (`brew install ddgr`) and retry. |
| 2 | Engine returned no results or query failed. |

The caller (shell or agent) is responsible for deciding what to do on a non-zero exit.

---

## What `websearch` is and is not

It **is** a faithful CLI projection of an installed search engine binary — the same discipline as `llm` over a device. It **is not** a search engine, an HTTP client, a scraper, or an LLM. It never touches your local files, never authenticates, and never retains any state between invocations. Every run is independent.
