#!/usr/bin/env bash
# agent-loop.sh — shell-loop agent over the llm coreutil
#
# The thesis in one script: one agent turn IS a shell job; the loop is the
# script with state wrapped around it. State lives in $CONV (messages.jsonl on
# disk) — the AgentCtx at the floor: append-only, grows without bound. Managed
# RAM is the floor above; this is the ground floor.
#
# Usage:
#   CONV=<file.jsonl> TOOLS_DIR=<dir> [MAX_ITER=20] agent-loop.sh
#
# CONV      — path to the JSONL conversation file (one ChatMessage per line,
#             proto3JSON-encoded). Created externally before the first call.
#             The loop appends to it; never truncates.
# TOOLS_DIR — directory containing tool executables and their FunctionDefinition
#             JSON files:
#               tools/<name>     : executable — reads args JSON on stdin,
#                                  emits result text on stdout.
#               tools/<name>.json: FunctionDefinition (name/description/inputSchema).
# MAX_ITER  — hard stop-guard (default 20). Non-optional: an agent that loops
#             indefinitely on tool calls is a bug, not a feature.
#
# Output: the final assistant text on stdout.
# Errors: on stderr.
# Exit:   0 on clean text termination; 1 on stop-guard or dispatch error.
#
# ChatMessage wire format (proto3JSON, via chat-inference-dart ChatCodec):
#   FunctionCallContent: {"role":"CHAT_ROLE_ASSISTANT","content":[{"functionCall":{"id":"...","name":"...","argumentsJson":"..."}}]}
#   FunctionResultContent: {"role":"CHAT_ROLE_USER","content":[{"functionResult":{"callId":"...","content":[{"text":{"text":"..."}}],"isError":false}}]}
#   TextContent: {"role":"CHAT_ROLE_ASSISTANT","content":[{"text":{"text":"..."}}]}

set -euo pipefail

CONV="${CONV:-${1:-}}"
TOOLS_DIR="${TOOLS_DIR:-${2:-tools}}"
MAX_ITER="${MAX_ITER:-20}"

if [[ -z "$CONV" ]]; then
  echo "agent-loop: CONV is required (path to messages.jsonl)" >&2
  exit 1
fi

if [[ ! -f "$CONV" ]]; then
  echo "agent-loop: conversation file not found: $CONV" >&2
  exit 1
fi

iter=0
while true; do
  iter=$((iter + 1))
  if [[ $iter -gt $MAX_ITER ]]; then
    echo "agent-loop: stop-guard reached ($MAX_ITER iterations) — possible infinite tool loop" >&2
    exit 1
  fi

  # Build --function flags from all *.json files in TOOLS_DIR
  func_flags=()
  if [[ -d "$TOOLS_DIR" ]]; then
    for def in "$TOOLS_DIR"/*.json; do
      [[ -f "$def" ]] && func_flags+=(--function "$def")
    done
  fi

  # Run one LLM turn — appends the assistant message to CONV
  cat "$CONV" | llm --input-format jsonl --output-format jsonl "${func_flags[@]}" >> "$CONV"

  # Inspect the last line (the assistant message just appended)
  last_line=$(tail -n 1 "$CONV")

  # Count function calls in this turn — handles parallel tool use
  call_count=$(printf '%s' "$last_line" | jq '[.content[] | select(.functionCall)] | length')

  if [[ "$call_count" -gt 0 ]]; then
    # Dispatch ALL function calls in this turn, one function-result per callId.
    # Process substitution keeps the loop body in the current shell so exit works.
    while IFS= read -r call_json; do
      call_id=$(printf '%s' "$call_json" | jq -r '.id')
      call_name=$(printf '%s' "$call_json" | jq -r '.name')
      args_json=$(printf '%s' "$call_json" | jq -r '.argumentsJson')

      tool_path="$TOOLS_DIR/$call_name"
      if [[ ! -x "$tool_path" ]]; then
        echo "agent-loop: tool not found or not executable: $tool_path" >&2
        exit 1
      fi

      tool_output=""
      is_error="false"
      set +e
      tool_output=$(printf '%s' "$args_json" | "$tool_path")
      tool_exit=$?
      set -e
      [[ $tool_exit -ne 0 ]] && is_error="true"

      # Append function-result (proto3JSON: role=user, nested text content; -c = one line per message)
      jq -cn \
        --arg   callId   "$call_id" \
        --arg   result   "$tool_output" \
        --argjson isError "$is_error" \
        '{"role":"CHAT_ROLE_USER","content":[{"functionResult":{"callId":$callId,"content":[{"text":{"text":$result}}],"isError":$isError}}]}' >> "$CONV"

    done < <(printf '%s' "$last_line" | jq -c '.content[] | select(.functionCall) | .functionCall')

  else
    # No function calls — concatenate all text content and exit
    printf '%s' "$last_line" | jq -r '[.content[] | select(.text) | .text.text] | join("")'
    exit 0
  fi
done
