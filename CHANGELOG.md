## Unreleased

- **`manifest` is Place-aware (#9), with a places-only tightening.** Tree roots are now discovered through the Place primitive: every place enclosing the working directory (`Place.current` + its ancestors) contributes its `<place>/.bentos/tree` when present, nearest-first — nested places cascade, per-FQDN nearest-wins. Home falls out as the implicit place in the chain; `BENTOS_TREE_PATH` stays the explicit prepended override. **Breaking:** a `.bentos/tree` at an UNMARKED directory is no longer discovered — mark your project as a place (`place init`) for its tree to be found, or point `BENTOS_TREE_PATH` at it.

## 0.1.0

- Initial release.
- `BentosChatDevice` — `ChatDevice` implementation over `/dev/llm/*` using the BentOS driver channel.
- `InProcessBentos` — in-process kernel stub for testing drivers without a socket.
- `boot.dart` — vendor-agnostic boot registry (`registerLlmDriver` / `bootLlmDevice`).
- Coreutils: `llm`, `chatbot`, `chat`, `chat-data`, `chat-render`, `tx`, `websearch`.
- `agent-loop.sh` — reference shell agent loop (parallel dispatch, stop-guard).
- Conformance suite aggregator — runs the `ChatDriverHarness` against all bundled drivers.
