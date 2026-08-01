/// The `reference-transaction` shim — the entity's whole nervous system, and
/// the one part of this package that is not Dart.
///
/// # Why shell
///
/// The hook fires on **every ref update** — every action, and every ref of
/// every push. A VM start on that path would be paid on all of them, so Dart
/// never runs here. The shim is generated shell, installed per installation,
/// and it is a program with its own contract: phase in argv, `old new ref`
/// lines on stdin, exit code as its whole answer. That makes it testable on its
/// own, with no repository and no Dart anywhere.
///
/// It spawns `git` while the [Git] port exists precisely to contain that. There
/// is no contradiction and no exception being carved: the port is Dart's seam
/// against a subprocess it cannot fake, and nothing in this file is Dart. The
/// seam guard's tell is the Dart string literal, which is why it does not fire
/// here.
///
/// # Why it locates itself from its own path
///
/// Git runs hooks out of the **common** directory always, including when the
/// update arrives from a worktree — so `dirname $0/..` *is* the entity. Asking
/// Git instead (`--absolute-git-dir` from inside a worktree) resolves to that
/// worktree's private directory, where no table lives, and the entity then
/// looks armed, fires nothing, and says nothing. Self-location makes that
/// failure impossible rather than merely forbidden, and it survives a moved
/// repository into the bargain.
///
/// # The phase mapping
///
/// Git's three transaction phases carry the ontology's three: `prepared` is
/// `.attempted` — the commit object exists, the ref has not moved, and a
/// non-zero exit **aborts the update**, which is where an entity refuses what
/// is illegal. `committed` is `.landed`, woken detached, because a landing is
/// never held hostage to what it wakes. `aborted` is `.refused`, likewise
/// detached.
///
/// # What is not an action
///
/// A ref's birth and its deletion are not acts upon an object, and genesis is
/// the structure instances are born from rather than one of them. All three are
/// skipped, which is why creating an instance never wakes a listener.
library;

/// The shim's source, installed verbatim as
/// `<entity>/hooks/reference-transaction`, mode 755.
const String referenceTransactionShim = r'''#!/usr/bin/env bash
# reference-transaction — the entity's nervous system. Generated; do not edit.
#
# Contract:  argv[1] = prepared | committed | aborted
#            stdin   = one "<old> <new> <ref>" line per ref in the transaction
#            exit    = non-zero at `prepared` ABORTS the whole transaction
#
# Tables (per installation, beside the repository, outside every tree):
#   $REPO/bentos/attempted   run in line; a non-zero exit refuses the act
#   $REPO/bentos/landed      woken detached
#   $REPO/bentos/refused     woken detached
# Line format, tab-separated:
#   <id>\t<instance-glob>\t<action-glob>\t<command...>
# Each command is called as: <cmd> <repo> <ref> <old> <new> <action>

set -uo pipefail

phase="${1:-}"
case "$phase" in
  prepared)  table_name=attempted; hold=1 ;;
  committed) table_name=landed;    hold=0 ;;
  aborted)   table_name=refused;   hold=0 ;;
  *) exit 0 ;;
esac

# Self-location. Git runs hooks from the COMMON dir, so this is the entity
# itself — asking git would answer with a worktree's private dir and fail silent.
REPO=$(cd "$(dirname "$0")/.." && pwd)
TABLE="$REPO/bentos/$table_name"
[ -f "$TABLE" ] || exit 0

# Children must not inherit this transaction's Git environment.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_QUARANTINE_PATH

ZERO=0000000000000000000000000000000000000000
LOG="$REPO/bentos/reactor.log"

while read -r old new ref; do
  case "$ref" in refs/heads/*) ;; *) continue ;; esac
  [ "$old" = "$new" ] && continue
  [ "$old" = "$ZERO" ] && continue                   # a birth is not an act
  [ "$new" = "$ZERO" ] && continue                   # nor is a deletion
  [ "$ref" = "refs/heads/genesis" ] && continue      # nor is the structure

  instance="${ref#refs/heads/}"
  action=$(git --git-dir="$REPO" cat-file commit "$new" 2>/dev/null \
           | sed -n 's/^Bentos-Action: //p' | head -n 1)
  [ -n "$action" ] || action="-"

  while IFS=$'\t' read -r id inst_glob act_glob cmd; do
    [ -z "${id:-}" ] && continue
    case "$id" in \#*) continue ;; esac
    [ -n "${cmd:-}" ] || continue
    # shellcheck disable=SC2254
    case "$instance" in $inst_glob) ;; *) continue ;; esac
    # shellcheck disable=SC2254
    case "$action" in $act_glob) ;; *) continue ;; esac

    if [ "$hold" = "1" ]; then
      if ! $cmd "$REPO" "$ref" "$old" "$new" "$action" >>"$LOG" 2>&1; then
        echo "entity: refused by $id: $cmd" >&2
        exit 1
      fi
    else
      nohup $cmd "$REPO" "$ref" "$old" "$new" "$action" >>"$LOG" 2>&1 &
    fi
  done < "$TABLE"
done

exit 0
''';
