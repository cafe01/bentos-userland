#!/usr/bin/env bash
#
# chat-breadboard.sh — the `chat` turn as a schematic.
#
# This is a breadboard, not a product: the program IS the logical form. Each
# part on the board is a named slot — a variable or a function — so any one
# component can be repopulated or tweaked in isolation without touching the
# wiring. The "board" section is the schematic itself.
#
# The species: a simple evolution of the LUCA (`... | llm | ...`, pure stateless
# cognition) that gains exactly three things — persistence (the tx log), a basic
# outward tool (web search), and decomposition as a shell job (the shell is the
# REPL). No brain, no AgentCtx — a later species, reached organically.
#
# THE SPINE — everything is a transaction, the turn is idempotent:
#
#   Entering a message into the log is a transaction BY ITSELF. The prompt is an
#   event; emitting it just appends and commits — it is NOT processed in the same
#   breath. Processing the log is a SEPARATE pipeline, and a perfect state machine:
#   decode the log, look at the last message, advance ONE step, append the result.
#
#     last = user / tool result   → the model owes a reply  → infer, append
#     last = assistant tool_calls → the model asked for tools → run them, append
#     last = assistant final      → terminal → NOOP (nothing to do)
#
#   The turn is idempotent: run the processor on a terminal log and nothing
#   happens. The agent's function-call loop stops on its own — not by a counter,
#   but because decoding the log shows there is nothing left to do.
#
set -euo pipefail

# ── Component values (the parts — populate / tweak these in isolation) ────────

ENTITY="${BENTOS_AGENT:-alfred}"          # whose tx session these transactions land in
DEVICE="openai/gpt-4o-mini"               # the /dev/llm device the cognition opens
TOOLS="./tools"                           # dir of tool executables + *.json defs (web search)
SYSTEM="You are a helpful assistant."     # system prompt

# ── Components (each a swappable block — same seams in, same seams out) ───────

# R — the stimulus emitter. Swap THIS to change the whole user experience; the
#     rest of the board never notices. The duality lives here:
#       bare on a TTY  → steals the terminal, interactive box, Ctrl-D sends
#       in a pipe/argv → one-shot, reads stimulus from argv or stdin, exits
emit()    { prompt; }                            # default UX: interactive box
# emit()  { echo "$1"; }                         # scripted: stimulus from argv
# emit()  { llm -d "$DEVICE" "open with a question about Dart"; }  # SYNTHETIC stimulus
# emit()  { cat fixtures/turn-01.txt; }          # bench / replay

# fetch — read the accumulated session (opaque bytes; tx never reads them)
fetch()   { tx cat -a "$ENTITY"; }

# decode — the wire into messages (chat-codec: only chat speaks the record)
decode()  { chat-codec decode; }

# encode — a mutation back into the wire
encode()  { chat-codec encode; }

# store — append a transaction to the log (content-blind commit)
store()   { tx append -a "$ENTITY"; }

# cognize — the cognition. The LUCA, untouched by the evolution: no state, no disk.
cognize() { llm -d "$DEVICE" -t "$TOOLS" -s "$SYSTEM"; }

# run_tools — execute the tool calls the model asked for, emit their results
run_tools() { chat-codec fold-calls -t "$TOOLS"; }   # slot: dispatch + collect

# render — a reply to the terminal (decode back, then the projection)
render()  { chat-codec decode | chat-render; }

# state — the conversation's current state: the role/shape of the last message.
#   The single input to the state machine. Slot to populate.
state()   { fetch | decode | chat-codec last; }

# ── The board (the wiring — this is the schematic; don't edit it to tweak) ────

# TRANSACTION 1 — the stimulus enters the log. Framed as a user event, appended,
# committed. A transaction by itself. Not processed here.
ingest() {
  echo "$1" | chat-codec as-user | encode | store
}

# TRANSACTION 2..N — advance the state machine by ONE idempotent step.
# Returns 0 if it did work (more may remain); non-zero at a terminal log (NOOP).
process() {
  case "$(state)" in
    user | tool)            # the model owes a reply → infer
      fetch | decode | cognize | encode | tee >(render) | store ;;
    assistant_tool_calls)   # the model asked for tools → run them
      fetch | decode | run_tools | encode | store ;;
    assistant_final | "")   # terminal → nothing to do
      return 1 ;;
  esac
}

# L — the loop is the shell. R: a stimulus enters (its own transaction); then
# drive the state machine to terminal (each step its own transaction); repeat.
repl() {
  local stimulus
  while stimulus="$(emit)"; do     # Ctrl-D closes the box → emit fails → loop ends
    ingest "$stimulus"             # transaction 1: the event lands, committed
    while process; do :; done      # advance to terminal; NOOP stops it
  done
}

repl
