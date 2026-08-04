#!/usr/bin/env sh
# bootstrap.sh — put `bentos` on a machine that has nothing.
#
#   curl -fsSL <url>/bootstrap.sh | sh
#
# This fetches exactly one thing and exits. Everything after — installing the
# coreutils, updating them, updating itself — is the binary's own job. Nothing
# else ever lands in this file: the moment a feature is added here it has to be
# maintained on every host, which is the packaging tax the release model exists
# to avoid.
#
# It works on both sides of the public seam: with a token while the repos are
# private, anonymously once they open. Nothing else changes.
#
# Where it lands is not a choice: `$BENTOS_HOME/bin` is the directory the
# installer owns and substitutes into, and staging happens inside the same home
# so that every rename stays on one filesystem — `rename(2)` across filesystems
# fails with EXDEV rather than degrading to a copy.
#
# Env:
#   BENTOS_HOME       the installer's own root      (default: $HOME/.bentos)
#   GH_TOKEN          token, if the repo is private (also honours GITHUB_TOKEN)
#   BENTOS_REPO       stream to install from        (default: cafe01/bentos-userland)
#   BENTOS_TAG_PREFIX release series in that repo   (default: v)

set -eu

EXEC_NAME="bentos"
REPO="${BENTOS_REPO:-cafe01/bentos-userland}"
TAG_PREFIX="${BENTOS_TAG_PREFIX:-v}"
BENTOS_HOME="${BENTOS_HOME:-$HOME/.bentos}"
PREFIX="$BENTOS_HOME/bin"
STAGING="$BENTOS_HOME/staging"
TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
API="https://api.github.com/repos/$REPO"

die() { echo "bentos: $*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required and was not found"; }
need curl

# curl against the API, carrying the token only when there is one — the same
# code path both sides of the seam.
api() {
  if [ -n "$TOKEN" ]; then
    curl -fsSL -H "Authorization: Bearer $TOKEN" "$@"
  else
    curl -fsSL "$@"
  fi
}

# ── platform ────────────────────────────────────────────────────────────────
# The manifest's vocabulary, <os>-<arch>, and nothing else is guessed: an
# unknown host is told so rather than handed a binary that cannot run.
os=$(uname -s)
case "$os" in
  Linux)  os="linux" ;;
  Darwin) os="macos" ;;
  *)      die "unsupported operating system: $os" ;;
esac
arch=$(uname -m)
case "$arch" in
  x86_64|amd64)  arch="x64" ;;
  arm64|aarch64) arch="arm64" ;;
  *)             die "unsupported architecture: $arch" ;;
esac
PLATFORM="$os-$arch"

# ── the release ─────────────────────────────────────────────────────────────
# Resolved by tag prefix and never by `latest`: one repo carries several
# products, and `latest` is whichever of them published most recently.
releases=$(api "$API/releases?per_page=100" 2>/dev/null) \
  || die "cannot read releases of $REPO (private repo? set GH_TOKEN)"
# Ordered by version and not by the API's own order, which is neither creation
# nor version order and cannot be relied on to put the newest release first.
TAG=$(echo "$releases" | grep -o '"tag_name": *"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/' \
       | grep "^$TAG_PREFIX" | sort -V -r | head -n 1)
[ -n "$TAG" ] || die "no release tagged $TAG_PREFIX* in $REPO"

release=$(api "$API/releases/tags/$TAG") || die "cannot read release $TAG"

# The release's assets, one per line: name, the API URL, the public URL.
#
# Read with awk rather than a JSON parser because this script runs before
# anything is installed — the clean machine has no jq and no Dart. An asset's
# own `url` field is the API endpoint that serves private content, so it is also
# what marks the start of an asset object and keeps the release's own `name`
# and the uploader's fields out of the reading.
asset_table() {
  echo "$release" | awk '
    /"url": *"[^"]*\/releases\/assets\/[0-9]+"/ { apiurl = $0; sub(/^[^:]*: *"/, "", apiurl); sub(/",?$/, "", apiurl); name = "" }
    apiurl != "" && name == "" && /"name": *"/ { name = $0; sub(/^[^:]*: *"/, "", name); sub(/",?$/, "", name) }
    apiurl != "" && /"browser_download_url": *"/ {
      dl = $0; sub(/^[^:]*: *"/, "", dl); sub(/",?$/, "", dl)
      print name "\t" apiurl "\t" dl
      apiurl = ""; name = ""
    }'
}

# With a token the API endpoint is the only one that serves a private asset;
# without one the public URL needs no auth. Same call site either way.
fetch_asset() {
  row=$(asset_table | grep "^$1	") || return 1
  if [ -n "$TOKEN" ]; then
    api -H "Accept: application/octet-stream" -o "$2" "$(echo "$row" | cut -f2)"
  else
    curl -fsSL -o "$2" "$(echo "$row" | cut -f3)"
  fi
}

# Staged inside the installer's own home and never in the machine's temp: the
# last act of this script is a rename into $PREFIX, and $TMPDIR is a different
# filesystem on most hosts, where that rename fails outright.
mkdir -p "$STAGING"
tmp=$(mktemp -d "$STAGING/bootstrap.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

# ── the manifest decides ────────────────────────────────────────────────────
# What is downloaded and what it must hash to are read from the release's own
# manifest, never assembled from a naming convention here.
fetch_asset "bentos-release.json" "$tmp/manifest.json" \
  || die "release $TAG carries no bentos-release.json"

# One line per artifact: name, platform, asset, sha256.
entry=$(awk '
    /^ *}/ { if (name != "") print name "\t" platform "\t" asset "\t" sha; name = platform = asset = sha = "" }
    { v = $0; sub(/^[^:]*: *"?/, "", v); sub(/"?,?$/, "", v) }
    /"name": *"/     { name = v }
    /"platform": *"/ { platform = v }
    /"asset": *"/    { asset = v }
    /"sha256": *"/   { sha = v }
  ' "$tmp/manifest.json" | grep "^$EXEC_NAME	$PLATFORM	" | head -n 1)

if [ -z "$entry" ]; then
  die "release $TAG has no $EXEC_NAME built for $PLATFORM — nothing was installed"
fi
ASSET=$(echo "$entry" | cut -f3)
WANT=$(echo "$entry" | cut -f4)
[ -n "$ASSET" ] && [ -n "$WANT" ] || die "malformed artifact entry for $EXEC_NAME in $TAG"

echo "bentos: $TAG · $PLATFORM · $ASSET"
fetch_asset "$ASSET" "$tmp/$EXEC_NAME" || die "release $TAG declares $ASSET and does not carry it"

# ── verify, then substitute ─────────────────────────────────────────────────
# The hash is checked before anything is placed, and the rename into PREFIX is
# the last act, so an interrupted run never leaves a half-written binary where
# a working one was.
if command -v sha256sum >/dev/null 2>&1; then
  GOT=$(sha256sum "$tmp/$EXEC_NAME" | cut -d' ' -f1)
elif command -v shasum >/dev/null 2>&1; then
  GOT=$(shasum -a 256 "$tmp/$EXEC_NAME" | cut -d' ' -f1)
else
  die "no sha256 tool found (sha256sum or shasum)"
fi
[ "$GOT" = "$WANT" ] || die "sha256 mismatch for $ASSET — expected $WANT, got $GOT"

mkdir -p "$PREFIX"
chmod +x "$tmp/$EXEC_NAME"
mv "$tmp/$EXEC_NAME" "$PREFIX/$EXEC_NAME"

echo "bentos: installed $PREFIX/$EXEC_NAME"
case ":$PATH:" in
  *":$PREFIX:"*) ;;
  *) echo "bentos: $PREFIX is not on your PATH — add it with:" >&2
     echo "         export PATH=\"$PREFIX:\$PATH\"" >&2 ;;
esac
echo "bentos: next — bentos install"
