#!/usr/bin/env bash
# chat.sh — THE SCHEMATIC. One turn, end to end: input -> turn -> output.
#
# Composes the three logical components; the transcript is the state they thread.
# This script IS the circuit drawing — read it top to bottom as a wiring diagram.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATH="$here:$PATH"                       # the logical components resolve as commands
TRANSCRIPT="${TRANSCRIPT:-$(mktemp -t chat-transcript.XXXXXX).jsonl}"

# The delta's fate is ONE logical operation: render it live AND fold it into the
# transcript — the event stream flows once, the shell tees it. (Tomorrow the same
# seam also commits into the entity — the same logical block, one more leg.)
dispatch_delta() { tee >(chat-render.sh --no-ansi >&2) | chat-codec fold >> "$TRANSCRIPT"; }

# INPUT — a human utterance (argv) or the synthetic signal generator (no argv).
{ if [[ $# -gt 0 ]]; then chat-prompt.sh "$@"; else chat-fixture.sh; fi; } >> "$TRANSCRIPT"

# TURN — context in, assistant delta out -> dispatched.
chat-turn.sh < "$TRANSCRIPT" | dispatch_delta

# The shell owns the loop: wrap these two stages in `while read` for multi-turn.
echo "--- transcript: $TRANSCRIPT ---" >&2
