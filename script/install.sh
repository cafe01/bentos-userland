#!/usr/bin/env bash
# install.sh — AOT-compile and install bentos-userland coreutils.
#
# Run from the package root (lib/bentos-userland).
#
# The registry is not here: it is bentos-release.json at the package root, read
# through tool/manifest.dart. That file is also what CI compiles and what the
# `bentos` installer fetches, so an executable can no longer exist in bin/ and
# be missing from the install (which is exactly how `entity` went uninstalled
# for a whole cycle). To add a coreutil, declare it in the manifest.
#
# This is the DEVELOPER path, on a campus checkout with the Dart SDK. The clean
# machine is `bentos`, not this script.
#
# Why AOT: `dart pub global activate` drops a launcher that re-resolves
# dependencies on every run and emits "Resolving dependencies..." to stderr.
# Under capture (pipes, command substitution) that noise corrupts the output.
# `dart compile exe` produces a clean standalone binary with zero resolve noise.
#
# Target dir: $PREFIX (default: $HOME/.local/bin). Override by setting PREFIX.
#
# Usage:  cd lib/bentos-userland && bash script/install.sh [name ...]
#   no args   — compile and install every executable the manifest declares
#   name ...  — install only the named ones (compiling the rest is skipped)
#
# Examples:
#   bash script/install.sh                 # install all
#   bash script/install.sh stt tts         # install only stt and tts
#   PREFIX=/usr/local/bin bash script/install.sh llm

set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local/bin}"
mkdir -p "$PREFIX"

MANIFEST="bentos-release.json"
if [[ ! -f "$MANIFEST" ]]; then
  echo "error: $MANIFEST not found — run from the package root (lib/bentos-userland)" >&2
  exit 2
fi
if ! command -v dart >/dev/null 2>&1; then
  echo "error: the Dart SDK is required to compile and to read the manifest" >&2
  exit 2
fi

# The host platform, in the manifest's own vocabulary. The manifest decides what
# is built here: an executable not declared for this platform is not our
# business today, even though the source sits in bin/.
case "$(uname -s)" in
  Linux)                       os="linux" ;;
  Darwin)                      os="macos" ;;
  MINGW*|MSYS*|CYGWIN*)        os="windows" ;;
  *)      echo "error: unsupported OS: $(uname -s)" >&2; exit 2 ;;
esac
case "$(uname -m)" in
  x86_64|amd64)  arch="x64" ;;
  arm64|aarch64) arch="arm64" ;;
  *)             echo "error: unsupported arch: $(uname -m)" >&2; exit 2 ;;
esac
PLATFORM="${os}-${arch}"

# name<TAB>entrypoint, one per line, for this platform.
mapfile -t EXECUTABLES < <(dart tool/manifest.dart plan "$PLATFORM")
if [[ ${#EXECUTABLES[@]} -eq 0 ]]; then
  echo "error: $MANIFEST declares nothing for $PLATFORM" >&2
  exit 2
fi

# Selective install: any args are the exec names to install. With no args the
# whole registry builds. Unknown names abort before any compile, so a typo
# never silently installs nothing.
if [[ $# -gt 0 ]]; then
  known_names=()
  for entry in "${EXECUTABLES[@]}"; do
    known_names+=("${entry%%$'\t'*}")
  done

  selected=()
  unknown=()
  for name in "$@"; do
    match=""
    for entry in "${EXECUTABLES[@]}"; do
      if [[ "${entry%%$'\t'*}" == "$name" ]]; then
        match="$entry"
        break
      fi
    done
    if [[ -n "$match" ]]; then
      selected+=("$match")
    else
      unknown+=("$name")
    fi
  done

  if [[ ${#unknown[@]} -gt 0 ]]; then
    echo "error: not declared for $PLATFORM in $MANIFEST: ${unknown[*]}" >&2
    echo "declared: ${known_names[*]}" >&2
    exit 2
  fi

  EXECUTABLES=("${selected[@]}")
fi

# Known-broken binaries and the reason each is blocked. Empty today: `bentos`
# was the one entry, declared in the manifest before its source existed, and it
# now compiles. A name left here after it builds is a registry that hides its
# own failure, which is the defect this file exists to prevent.
EXPECTED_FAIL=""
EXPECTED_FAIL_REASON=""

installed=()
failed=()
failed_expected=()

for entry in "${EXECUTABLES[@]}"; do
  exec_name="${entry%%$'\t'*}"
  src="${entry##*$'\t'}"
  dest="${PREFIX}/${exec_name}"

  printf "  compiling %-16s " "${exec_name}..."
  if dart compile exe "$src" -o "$dest" 2>/dev/null; then
    printf "ok → %s\n" "$dest"
    installed+=("$exec_name")
  else
    # Re-run to capture the error for display.
    err=$(dart compile exe "$src" -o "$dest" 2>&1 || true)
    if echo "$EXPECTED_FAIL" | grep -qw "$exec_name"; then
      printf "FAILED (expected — %s)\n" "$EXPECTED_FAIL_REASON"
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
echo "  manifest  : $MANIFEST v$(dart tool/manifest.dart version) · $PLATFORM"
if [[ ${#installed[@]} -gt 0 ]]; then
  echo "  installed : ${installed[*]}"
fi
if [[ ${#failed_expected[@]} -gt 0 ]]; then
  echo "  FAILED (expected, $EXPECTED_FAIL_REASON): ${failed_expected[*]}"
fi
if [[ ${#failed[@]} -gt 0 ]]; then
  echo "  FAILED (unexpected): ${failed[*]}"
fi
echo "────────────────────────────────────────────────────"

[[ ${#failed[@]} -eq 0 ]]
