#!/usr/bin/env bash
# agent_loop_test.sh — tests for examples/agent-loop.sh
#
# Stubs llm via PATH override + per-test state files. No API key required.
# Three scenarios:
#   1. single_tool_call  — one function call → dispatch → text response
#   2. parallel_calls    — two function calls in one turn → both dispatched → text
#   3. stop_guard        — llm always returns function call → MAX_ITER fires

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_LOOP="$SCRIPT_DIR/examples/agent-loop.sh"
TOOLS_DIR="$SCRIPT_DIR/examples/tools"

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$desc"
  else
    fail "$desc — expected '$expected', got '$actual'"
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    pass "$desc"
  else
    fail "$desc — expected to contain '$needle'"
  fi
}

# --- helpers ---

# make_fake_llm <bin_dir> <count_file> <turn_dir>
# Writes a fake llm that reads call count, increments it, and cats turn${n}.jsonl
make_fake_llm() {
  local bin_dir="$1" count_file="$2" turn_dir="$3"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/llm" << HEREDOC
#!/usr/bin/env bash
n=\$(cat "$count_file")
n=\$((n + 1))
echo \$n > "$count_file"
cat "$turn_dir/turn\${n}.jsonl"
HEREDOC
  chmod +x "$bin_dir/llm"
}

# --- test 1: single tool call ---
test_single_tool_call() {
  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" RETURN

  local count_file="$tmpdir/count"
  echo 0 > "$count_file"

  # turn 1: assistant requests one function call (echo "hello world")
  printf '%s\n' \
    '{"role":"CHAT_ROLE_ASSISTANT","content":[{"functionCall":{"id":"call_abc","name":"echo","argumentsJson":"{\"text\":\"hello world\"}"}}]}' \
    > "$tmpdir/turn1.jsonl"

  # turn 2: assistant returns text after seeing the tool result
  printf '%s\n' \
    '{"role":"CHAT_ROLE_ASSISTANT","content":[{"text":{"text":"Echo returned: hello world"}}]}' \
    > "$tmpdir/turn2.jsonl"

  make_fake_llm "$tmpdir/bin" "$count_file" "$tmpdir"

  local conv="$tmpdir/conv.jsonl"
  printf '%s\n' \
    '{"role":"CHAT_ROLE_USER","content":[{"text":{"text":"Please echo hello world"}}]}' \
    > "$conv"

  local output
  output=$(PATH="$tmpdir/bin:$PATH" CONV="$conv" TOOLS_DIR="$TOOLS_DIR" bash "$AGENT_LOOP")

  assert_eq  "single: llm called twice"          "2"                        "$(cat "$count_file")"
  assert_eq  "single: output is final text"      "Echo returned: hello world" "$output"

  local conv_content
  conv_content=$(cat "$conv")
  assert_contains "single: CONV has functionResult" '"functionResult"'   "$conv_content"
  assert_contains "single: CONV has correct callId"  '"callId":"call_abc"' "$conv_content"
  assert_contains "single: CONV has echo result"     '"hello world"'      "$conv_content"
}

# --- test 2: parallel tool calls (two in one turn) ---
test_parallel_calls() {
  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" RETURN

  local count_file="$tmpdir/count"
  echo 0 > "$count_file"

  # turn 1: two function calls in one assistant message
  printf '%s\n' \
    '{"role":"CHAT_ROLE_ASSISTANT","content":[{"functionCall":{"id":"call_1","name":"echo","argumentsJson":"{\"text\":\"first\"}"}},{"functionCall":{"id":"call_2","name":"echo","argumentsJson":"{\"text\":\"second\"}"}}]}' \
    > "$tmpdir/turn1.jsonl"

  # turn 2: text after seeing both results
  printf '%s\n' \
    '{"role":"CHAT_ROLE_ASSISTANT","content":[{"text":{"text":"Both echoed."}}]}' \
    > "$tmpdir/turn2.jsonl"

  make_fake_llm "$tmpdir/bin" "$count_file" "$tmpdir"

  local conv="$tmpdir/conv.jsonl"
  printf '%s\n' \
    '{"role":"CHAT_ROLE_USER","content":[{"text":{"text":"Echo two things"}}]}' \
    > "$conv"

  local output
  output=$(PATH="$tmpdir/bin:$PATH" CONV="$conv" TOOLS_DIR="$TOOLS_DIR" bash "$AGENT_LOOP")

  assert_eq "parallel: llm called twice"     "2"             "$(cat "$count_file")"
  assert_eq "parallel: output is final text" "Both echoed."  "$output"

  # Both function-results must have been appended (one per callId)
  local result_count
  result_count=$(grep -c '"functionResult"' "$conv" || true)
  assert_eq  "parallel: two function results in CONV" "2"          "$result_count"

  local conv_content
  conv_content=$(cat "$conv")
  assert_contains "parallel: callId call_1 in CONV"  '"callId":"call_1"' "$conv_content"
  assert_contains "parallel: callId call_2 in CONV"  '"callId":"call_2"' "$conv_content"
  assert_contains "parallel: result 'first' in CONV" '"first"'           "$conv_content"
  assert_contains "parallel: result 'second' in CONV" '"second"'         "$conv_content"
}

# --- test 3: stop-guard fires ---
test_stop_guard() {
  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" RETURN

  # Fake llm that always returns a function call — would loop forever without stop-guard
  local fake_bin="$tmpdir/bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/llm" << 'HEREDOC'
#!/usr/bin/env bash
echo '{"role":"CHAT_ROLE_ASSISTANT","content":[{"functionCall":{"id":"call_inf","name":"echo","argumentsJson":"{\"text\":\"loop\"}"}}]}'
HEREDOC
  chmod +x "$fake_bin/llm"

  local conv="$tmpdir/conv.jsonl"
  printf '%s\n' \
    '{"role":"CHAT_ROLE_USER","content":[{"text":{"text":"loop forever"}}]}' \
    > "$conv"

  local exit_code=0
  PATH="$fake_bin:$PATH" CONV="$conv" TOOLS_DIR="$TOOLS_DIR" MAX_ITER=3 bash "$AGENT_LOOP" \
    >/dev/null 2>&1 || exit_code=$?

  assert_eq "stop-guard: exits non-zero" "1" "$exit_code"

  # MAX_ITER=3 → exactly 3 llm calls → 3 function-call lines in CONV
  local call_count
  call_count=$(grep -c '"functionCall"' "$conv" || true)
  assert_eq "stop-guard: fired after MAX_ITER iterations" "3" "$call_count"
}

# --- run ---
test_single_tool_call
test_parallel_calls
test_stop_guard

echo ""
if [[ $FAIL -eq 0 ]]; then
  echo "All $PASS tests passed."
  exit 0
else
  echo "$FAIL/$((PASS + FAIL)) tests FAILED."
  exit 1
fi
