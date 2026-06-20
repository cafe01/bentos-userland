#!/usr/bin/env bash
# install.sh — AOT-compile and install bentos-userland coreutils.
#
# Run from the package root (lib/bentos-userland).
#
# Why AOT: `dart pub global activate` drops a launcher that re-resolves
# dependencies on every run and emits "Resolving dependencies..." to stderr.
# Under capture (pipes, command substitution) that noise corrupts the output.
# `dart compile exe` produces a clean standalone binary with zero resolve noise.
#
# Target dir: $PREFIX (default: $HOME/.local/bin). Override by setting PREFIX.
# Usage:  cd lib/bentos-userland && bash script/install.sh
#         PREFIX=/usr/local/bin bash script/install.sh

set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local/bin}"
mkdir -p "$PREFIX"

# Executable name → bin/ source file (pubspec.yaml executables: section).
# Format: "exec-name:bin_file"  (file has no .dart suffix here)
EXECUTABLES=(
  "chat:chat"
  "chat-codec:chat_codec"
  "chat-render:chat_render"
  "chatbot:chatbot"
  "llm:llm"
  "tx:tx"
  "websearch:websearch"
)

# Known-broken binaries and the reason each is blocked:
#   chat, chatbot  — consume the retired package:tx API (pending #30 rewire)
#   chat-codec, chat-render, llm — Encoding/inputEncoding API mismatch; blocked
#                   on the chat-inference-dart submodule pointer being bumped in
#                   the parent repo (pending pointer bump after #30 sweep)
EXPECTED_FAIL="chat chatbot chat-codec chat-render llm"

installed=()
failed=()
failed_expected=()

for entry in "${EXECUTABLES[@]}"; do
  exec_name="${entry%%:*}"
  bin_file="${entry##*:}"
  src="bin/${bin_file}.dart"
  dest="${PREFIX}/${exec_name}"

  printf "  compiling %-16s " "${exec_name}..."
  if dart compile exe "$src" -o "$dest" 2>/dev/null; then
    printf "ok → %s\n" "$dest"
    installed+=("$exec_name")
  else
    # Re-run to capture the error for display.
    err=$(dart compile exe "$src" -o "$dest" 2>&1 || true)
    if echo "$EXPECTED_FAIL" | grep -qw "$exec_name"; then
      printf "FAILED (expected — pending pointer bump / #30)\n"
      failed_expected+=("$exec_name")
    else
      printf "FAILED (unexpected)\n"
      echo "$err" | sed 's/^/    /' >&2
      failed+=("$exec_name")
    fi
  fi
done

echo ""
echo "── install report ──────────────────────────────────"
if [[ ${#installed[@]} -gt 0 ]]; then
  echo "  installed : ${installed[*]}"
fi
if [[ ${#failed_expected[@]} -gt 0 ]]; then
  echo "  FAILED (expected, pending #30): ${failed_expected[*]}"
fi
if [[ ${#failed[@]} -gt 0 ]]; then
  echo "  FAILED (unexpected): ${failed[*]}"
fi
echo "────────────────────────────────────────────────────"

[[ ${#failed[@]} -eq 0 ]]
