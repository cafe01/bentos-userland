#!/usr/bin/env bash
# chat-turn — TURN stage (the black box; the generic agent-loop, chat-configured).
#
# Logical role: advance the conversation by exactly one step.
#   in:  the full transcript (ChatMessage JSONL) on stdin — the context
#   out: the assistant's delta as a ChatEvent stream on stdout
#
# The skeleton is invariant — input → [this box] → output — seen from outside and
# from inside. Chat-without-tools is the degenerate branch (infer only); the agent
# is the SAME box with the tools branch wired. Continuity lives in the input
# (the transcript), never in this process: it is stateless and exits.
set -euo pipefail

# --- internal logic, each operation named so the circuit reads as pure logic ---

last_role() {
  # transcript on stdin -> the role of its last message (CHAT_ROLE_USER|…)
  tail -n1 | grep -oE 'CHAT_ROLE_[A-Z]+' | head -n1
}

next_state() {
  # transcript on stdin -> what this step owes: infer | tools | done
  case "$(last_role)" in
    CHAT_ROLE_USER)      echo infer ;;  # the human spoke -> answer
    CHAT_ROLE_ASSISTANT) echo done  ;;  # already answered -> terminal
    *)                   echo done  ;;
  esac
}

infer() {
  # the capability, abstracted. Fake signal generator now; swap this body for
  # `llm …` (fed the transcript) at the edge, last. The contract is the event stream.
  chat-codec event \
    text_start \
    "text_delta:O BentOS é um sistema operacional para seres de software — " \
    "text_delta:agentes e apps vivos que se compõem por pipelines." \
    text_stop \
    "complete:end_turn"
}

run_tools() { :; }  # the agent branch — stubbed in this first pass, present in the shape

# --- the circuit (pure logic) ---
transcript="$(cat)"
case "$(next_state <<<"$transcript")" in
  infer) infer ;;
  tools) run_tools ;;
  done)  : ;;  # NOOP — the log already shows terminal; no counter needed
esac
