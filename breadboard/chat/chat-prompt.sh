#!/usr/bin/env bash
# chat-prompt — INPUT stage (emit, live).
#
# Logical role: turn a human utterance into one user message on the wire.
#   in:  text  (argv; or stdin when no argv — so fixtures pipe straight in)
#   out: one ChatMessage JSONL line, role=user
#
# Physical component abstracted here: chat-codec (the ontology constructor).
# We name the role, not the syntax — swap the codec and this contract holds.
set -euo pipefail

text="${*:-$(cat)}"
chat-codec message --user "$text"
