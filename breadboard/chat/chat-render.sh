#!/usr/bin/env bash
# chat-render — OUTPUT stage (render).
#
# Logical role: project the wire into something a human reads.
#   in:  a ChatEvent stream on stdin
#   out: styled, human-readable text
#
# Physical component abstracted: the chat-render coreutil. This thin face exists
# so the schematic names an OUTPUT role, not an executable — the body can change.
set -euo pipefail
exec chat-render "$@"
