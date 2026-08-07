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

/// The shim installed at `<entity>/hooks/reference-transaction`, mode 755, for
/// the installation answering to [entity].
///
/// The name is interpolated rather than derived, because `<plot>/<name>/repo.git`
/// is a layout Dart decides and a shell would have to re-derive — the same fact
/// decided twice is how one file stays right while its neighbour goes wrong.
/// Single-quoted with the shell's own escape, so a name holding a quote or a
/// newline is carried rather than refused: the value is a directory name and
/// this file is the last place that could mangle it.
String referenceTransactionShimFor(String entity) =>
    _shimTemplate.replaceAll(_entityPlaceholder, entity.replaceAll("'", r"'\''"));

/// What the template carries where the installation's name belongs.
const String _entityPlaceholder = '__BENTOS_ENTITY__';

const String _shimTemplate = r'''#!/usr/bin/env bash
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
#   <id>\t<instance-glob>\t<action-glob>\t<always|once>\t<provenance>\t--\t<arg>...
# Each command is called as: <cmd> <repo> <ref> <old> <new> <action>
# and with the occurrence in its environment:
#   BENTOS_ENTITY BENTOS_INSTANCE BENTOS_EVENT BENTOS_PHASE BENTOS_NOUN
#   BENTOS_SHA   the act's commit — the value the ref takes
#   BENTOS_OLD   the value it held before it — the act's PARENT
#
# BENTOS_OLD is not a convenience. A gate at `prepared` judges whether the act
# is legal AT ITS PARENT, and at that moment the ref still holds the old value —
# so a gate that folded the tip would be leaning on Git's transaction timing to
# be right. The parent rides argv too, but a body reached through `entity run`
# is a grandchild and argv does not survive that hop; the environment does.
#
# The environment is what lets a line armed on `*` wake something that knows
# WHERE the event landed: the instance is not in the line, because at the moment
# a manifest is armed no instance exists yet.
#
# The provenance column is read only when `--` stands behind it; a line without
# one was armed by hand, which is what every line written before it was.
#
# The `--` opens the command block and every argument is its own field, so an
# argument holding a space survives the table. A tail without it was written
# before that and is split on whitespace, which is what it has always meant.
#
# A `once` line is pruned from its table at the moment it matches and BEFORE
# its command runs — so it can never fire twice, including at `prepared`, where
# a refusal exits this script immediately. The table is replaced by rename, so
# the loop reading it keeps the file it opened.

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
TAB=$'\t'

# The installation's own name, written here when the shim was installed. Every
# woken command learns which entity spoke without deriving it from a path.
export BENTOS_ENTITY='__BENTOS_ENTITY__'
export BENTOS_PHASE="$table_name"

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

  # The occurrence, in the environment of everything woken below: WHERE it
  # landed and WHAT landed. A line armed on `*` is not a line that lost the
  # instance — the instance is here, and it is the truth of this transaction
  # rather than of whoever armed the line.
  export BENTOS_INSTANCE="$instance"
  export BENTOS_NOUN="$action"
  export BENTOS_EVENT="$action.$table_name"
  export BENTOS_SHA="$new"
  export BENTOS_OLD="$old"

  while IFS=$'\t' read -r id inst_glob act_glob life cmd; do
    [ -z "${id:-}" ] && continue
    case "$id" in \#*) continue ;; esac
    # A line written before the lifetime column existed: the tail is all
    # command, and it lives forever. Reading it any other way would silently
    # eat its first argument.
    case "${life:-}" in
      once|always) ;;
      *) cmd="${life:-}${cmd:+$TAB$cmd}"; life=always ;;
    esac
    [ -n "${cmd:-}" ] || continue

    # The provenance column, when one stands there. Recognised only with the
    # sentinel behind it, so a line from before this column whose command begins
    # with one of these words is not mistaken for a marked one.
    case "${cmd%%$TAB*}" in
      hand|manifest)
        after="${cmd#*$TAB}"
        [ "${after%%$TAB*}" = "--" ] && cmd="$after"
        ;;
    esac

    # The command block. With the sentinel, one field per argument — read as an
    # array so the boundaries the caller drew are the boundaries exec sees.
    # Without it, a line from before the sentinel: split on whitespace, which is
    # the only reading that keeps doing what that line has always done.
    if [ "${cmd%%$TAB*}" = "--" ]; then
      argv=()
      rest="${cmd#--$TAB}"
      while [ -n "$rest" ]; do
        argv+=("${rest%%$TAB*}")
        case "$rest" in
          *"$TAB"*) rest="${rest#*$TAB}" ;;
          *) rest="" ;;
        esac
      done
    else
      # shellcheck disable=SC2206
      argv=($cmd)
    fi
    [ "${#argv[@]}" -gt 0 ] || continue
    # shellcheck disable=SC2254
    case "$instance" in $inst_glob) ;; *) continue ;; esac
    # shellcheck disable=SC2254
    case "$action" in $act_glob) ;; *) continue ;; esac

    # Fired means spent. Pruned before the command runs, because at `prepared` a
    # refusal leaves this script by `exit 1` and would never come back for it.
    if [ "$life" = "once" ]; then
      pruned="$TABLE.$$"
      grep -v "^$id$TAB" "$TABLE" > "$pruned" 2>/dev/null
      mv -f "$pruned" "$TABLE"
    fi

    if [ "$hold" = "1" ]; then
      # A REFUSAL SPEAKS TO THE CALLER, not only to the log. The gate's own
      # sentence — `'prompt' is illegal at owes_inference` — is the whole of
      # what a person needs, and sending them to a log file to find it is a
      # refusal that refuses twice. So a held command's output is buffered, kept
      # in the log as always, and echoed to stderr when it says no: git carries
      # this stream up through `update-ref`, which is where the floor above
      # reads it. Buffered and not streamed, because interleaving two gates into
      # one stream would make neither readable; a gate that runs long enough for
      # that to matter is a gate that is already wrong.
      out="$REPO/bentos/refusal.$$"
      if "${argv[@]}" "$REPO" "$ref" "$old" "$new" "$action" >"$out" 2>&1; then
        cat "$out" >> "$LOG"
        rm -f "$out"
      else
        cat "$out" >> "$LOG"
        echo "entity: refused by $id: ${argv[*]}" >&2
        cat "$out" >&2
        rm -f "$out"
        exit 1
      fi
    else
      nohup "${argv[@]}" "$REPO" "$ref" "$old" "$new" "$action" >>"$LOG" 2>&1 &
    fi
  done < "$TABLE"
done

exit 0
''';
