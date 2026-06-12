## 0.1.0

- Initial release.
- `BentosChatDevice` — `ChatDevice` implementation over `/dev/llm/*` using the BentOS driver channel.
- `InProcessBentos` — in-process kernel stub for testing drivers without a socket.
- `boot.dart` — vendor-agnostic boot registry (`registerLlmDriver` / `bootLlmDevice`).
- Coreutils: `llm`, `chatbot`, `chat`, `chat-data`, `chat-render`, `tx`, `websearch`.
- `agent-loop.sh` — reference shell agent loop (parallel dispatch, stop-guard).
- Conformance suite aggregator — runs the `ChatDriverHarness` against all bundled drivers.
