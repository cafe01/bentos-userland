#!/usr/bin/env bash
# chat-fixture — INPUT stage (emit, synthetic).
#
# Logical role: the signal generator on the input axis — replay a canned turn (or
# a whole transcript fixture) with no human, so the circuit runs deterministically.
# Counterpart to chat-prompt: same OUT contract, no live operator.
#   in:  a fixture name (argv) → fixtures/<name>.jsonl ; or nothing → a default line
#   out: ChatMessage JSONL line(s)
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

name="${1:-}"
if [[ -n "$name" && -f "$here/fixtures/$name.jsonl" ]]; then
  cat "$here/fixtures/$name.jsonl"
else
  chat-codec message --user "olá, o que é o BentOS?"
fi
