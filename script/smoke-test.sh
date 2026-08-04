#!/usr/bin/env bash
# smoke-test.sh — the product proven from outside, the way a stranger meets
# it: the real `curl | sh`, against the real published release, in a home
# that never existed before this run.
#
# What this witnesses and what it never does:
#   - bytes in the prefix, hashed by this shell, never by `bentos` itself
#   - execution — every installed name actually runs, not just exists
#   - the word printed against the byte that moved, both witnessed the same
#     way, in the same command — a report that lies about its own bytes is
#     the exact class the unit suite cannot see, because there the report and
#     the assertion share one process
# state.json is never read: it is the "peça interna" this gate exists to stop
# trusting.
#
# Runnable by hand exactly as CI runs it — no CI-only branch anywhere here.
# Nothing published, tagged or pushed: read-only against the registry,
# write-only inside its own throwaway $HOME.
#
# Env:
#   BENTOS_REPO          which repo to prove       (default: cafe01/bentos-userland)
#   BENTOS_SMOKE_FLOOR    the pinned floor tag       (default: v0.1.1)
#
# The floor is a real release old enough to sit behind the latest one —
# pinned by name, never "whatever the previous release was". `update` itself
# still resolves the true latest the one way production ever does; this
# script never guesses what that is. Caveat named, not solved here: the pin
# works by tag-prefix startsWith, which today's tags (v0.1.1, v0.1.2, v0.1.3)
# make exact, but v0.1.10 would also start with "v0.1.1" — the day a tag like
# that is cut, this floor needs a prefix that cannot collide (or the
# mechanism it leans on needs an exact-match option).
#
# What "old enough" does NOT mean: that every name's bytes differ between the
# floor and the latest. A release that only changed `bentos` leaves every
# other coreutil byte-identical across the whole span — true the day this was
# written. Expecting movement everywhere is asserting on a world that may not
# exist; what this script asks instead is the manifest's own question: does
# the prefix hold what the *target* release declares, by name, by sha256 —
# true whether or not the bytes happened to move to get there, and read from
# the two manifests directly rather than assumed from the floor's age.

set -euo pipefail

REPO="${BENTOS_REPO:-cafe01/bentos-userland}"
FLOOR_TAG="${BENTOS_SMOKE_FLOOR:-v0.1.1}"

# The repo is public, so nothing here strictly needs a token — but this script
# makes over a dozen API calls in a few seconds, and GitHub's unauthenticated
# rate limit is 60/hour against a whole shared address, not just this run. CI
# already carries GITHUB_TOKEN; a developer's shell usually carries a `gh`
# login. Either raises the ceiling to 5000/hour and neither is required.
if [ -z "${GH_TOKEN:-}" ] && [ -z "${GITHUB_TOKEN:-}" ] && command -v gh >/dev/null 2>&1; then
  GH_TOKEN="$(gh auth token 2>/dev/null || true)"
  export GH_TOKEN
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"
mkdir -p "$HOME"
BIN="$HOME/.bentos/bin"
export PATH="$BIN:$PATH"

say()  { echo "smoke: $*"; }
step() { echo; echo "── $*"; }
fail() { echo "smoke: FAIL — $*" >&2; exit 1; }

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# The prefix's own bytes, one line per name — this shell's witness, never the
# store's. Declared once so every phase hashes the same way.
hash_prefix() {
  for f in "$BIN"/*; do
    [ -f "$f" ] && echo "$(basename "$f") $(sha256_of "$f")"
  done | sort
}

# The names that changed between two `hash_prefix` snapshots.
changed_names() {
  comm -13 <(echo "$1" | sort) <(echo "$2" | sort) | awk '{print $1}'
}

ls_prefix() { echo "$BIN:"; ls -la "$BIN" 2>/dev/null || echo "  (does not exist yet)"; }

# This host's own <os>-<arch> token, by the same mapping platform.dart uses —
# the manifest's `platform` field is read through this string and nothing else.
host_platform() {
  local os arch
  case "$(uname -s)" in
    Linux) os=linux ;;
    Darwin) os=macos ;;
    *) os=$(uname -s | tr '[:upper:]' '[:lower:]') ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) arch=x64 ;;
    arm64|aarch64) arch=arm64 ;;
    *) arch=$(uname -m) ;;
  esac
  echo "$os-$arch"
}

# The names this host's build of [name] holds under [tag] and [tag]'s own
# sha256 for it — read from the enriched manifest, never assumed from a
# release's age. A name absent from a release (no build for this host) is
# absent from the output, same as the installer's own reading.
manifest_shas() {
  local tag="$1" platform="$2"
  curl -fsSL "$(release_manifest_url "$tag")" \
    | jq -r --arg p "$platform" '.artifacts[] | select(.platform == $p) | "\(.name) \(.sha256)"' \
    | sort
}

# Names whose sha256 differs between two `manifest_shas` snapshots — what a
# name-blind "update always moves everything" assumption cannot say, and what
# the manifest itself answers regardless of which names a given release
# happened to touch.
differing_names() {
  comm -13 <(echo "$1" | sort) <(echo "$2" | sort) | awk '{print $1}'
}

release_manifest_url() {
  local tag="$1"
  if [ "$tag" = "latest" ]; then
    echo "https://github.com/$REPO/releases/latest/download/bentos-release.json"
  else
    echo "https://github.com/$REPO/releases/download/$tag/bentos-release.json"
  fi
}

# Every name on the PATH actually runs — the class of defect nothing but a
# real host catches: wrong architecture, a missing dynamic library, a
# corrupted transfer. No opinion on what a bare invocation prints or exits
# with (that varies by coreutil); only that the OS could load and start it.
assert_executes() {
  local capture="$WORK/exec-capture"
  for f in "$BIN"/*; do
    name=$(basename "$f")
    if "$f" >"$capture" 2>&1 </dev/null; then code=0; else code=$?; fi
    body=$(cat "$capture")
    if [ "$code" = "126" ] || [ "$code" = "127" ] || echo "$body" | grep -qiE 'cannot execute binary|exec format error|no such file or directory'; then
      fail "$name did not execute on this host (exit $code): $body"
    fi
    say "  ran $name — exit $code"
  done
}

# Cross-check: the word `bentos` printed against the bytes this shell
# independently hashed. [$3] is the set of names allowed to say "unchanged"
# and never "installed" or "restored"; every other name in [$4] must say
# "installed" or "restored" and never "unchanged".
assert_report_matches_bytes() {
  local report="$1" unchanged_expected="$2" moved_expected="$3"
  for name in $unchanged_expected; do
    echo "$report" | grep -E '^  installed' | grep -qw "$name" && fail "report says $name installed — its bytes did not move"
    echo "$report" | grep -E '^  restored'  | grep -qw "$name" && fail "report says $name restored — its bytes did not move"
  done
  for name in $moved_expected; do
    moved_ok=$(echo "$report" | grep -E '^  (installed|restored)' | grep -qw "$name" && echo yes || echo no)
    [ "$moved_ok" = "yes" ] || fail "$name's bytes moved and the report never said installed or restored"
  done
}

step "curl | sh against the published release ($REPO)"
curl -fsSL "https://github.com/$REPO/releases/latest/download/bootstrap.sh" | sh
[ -x "$BIN/bentos" ] || fail "bootstrap did not leave an executable bentos at $BIN/bentos"
assert_executes

step "pin the floor — install $FLOOR_TAG, the whole set"
mkdir -p "$HOME/.bentos"
cat >"$HOME/.bentos/config.toml" <<TOML
[streams.bentos-userland]
repo = "$REPO"
tag_prefix = "$FLOOR_TAG"
TOML
say "before:"; ls_prefix
bentos install
say "after:"; ls_prefix
after_floor=$(hash_prefix)
names=$(echo "$after_floor" | awk '{print $1}')
[ -n "$names" ] || fail "install left nothing in $BIN"
say "names: $names"
assert_executes

step "un-pin — the real default, the true latest, discovered and never guessed"
rm "$HOME/.bentos/config.toml"

step "read the manifests — what floor and latest each declare, by name and sha256"
PLATFORM=$(host_platform)
floor_shas=$(manifest_shas "$FLOOR_TAG" "$PLATFORM")
latest_shas=$(manifest_shas latest "$PLATFORM")
differing=$(differing_names "$floor_shas" "$latest_shas")
say "platform: $PLATFORM"
say "differ floor→latest: ${differing:-(none — this floor and latest are byte-identical for this host)}"
others=$(echo "$names" | grep -v '^bentos$')
bentos_differs=$(echo "$differing" | grep -qx bentos && echo yes || echo no)
others_differing=$(echo "$others" | grep -Fx -f <(echo "$differing") || true)
others_unchanged=$(echo "$others" | grep -vFx -f <(echo "$differing") || true)

step "self-update: only bentos may move, and only if its bytes actually differ"
report=$(bentos self-update)
echo "$report"
say "after:"; ls_prefix
after_self=$(hash_prefix)
moved=$(changed_names "$after_floor" "$after_self")
if [ "$bentos_differs" = "yes" ]; then
  [ "$moved" = "bentos" ] || fail "self-update moved {$moved}, expected only bentos"
  assert_report_matches_bytes "$report" "$others" "bentos"
else
  [ -z "$moved" ] || fail "self-update moved {$moved}, expected nothing — floor and latest agree on bentos"
  assert_report_matches_bytes "$report" "$names" ""
fi
assert_executes

step "update: every name whose bytes actually differ from the floor, self left alone"
report=$(bentos update)
echo "$report"
say "after:"; ls_prefix
after_update=$(hash_prefix)
moved=$(changed_names "$after_self" "$after_update")
[ -z "$(echo "$moved" | grep -x bentos || true)" ] || fail "update moved bentos again — self-update already put it on the latest version"
for n in $others_differing; do
  echo "$moved" | grep -qx "$n" || fail "update never moved $n off the floor, though the manifest says its bytes differ"
done
for n in $others_unchanged; do
  echo "$moved" | grep -qx "$n" && fail "update moved $n, though the manifest says floor and latest agree on it byte-for-byte" || true
done
assert_report_matches_bytes "$report" "bentos $others_unchanged" "$others_differing"
assert_executes

step "rollback: every name update actually moved, back to the floor's own bytes"
report=$(bentos rollback)
echo "$report"
say "after:"; ls_prefix
after_rollback=$(hash_prefix)
[ "$after_rollback" = "$after_floor" ] || fail "rollback did not reproduce the floor's own bytes byte-for-byte — a diff means it re-fetched instead of reusing what was already materialized"
rollback_moved_expected="$others_differing"; [ "$bentos_differs" = "yes" ] && rollback_moved_expected="bentos $rollback_moved_expected"
rollback_unchanged_expected="$others_unchanged"; [ "$bentos_differs" = "no" ] && rollback_unchanged_expected="bentos $rollback_unchanged_expected"
assert_report_matches_bytes "$report" "$rollback_unchanged_expected" "$rollback_moved_expected"
assert_executes

say "all green — $REPO installs, updates, rolls back and executes, proven from outside"
