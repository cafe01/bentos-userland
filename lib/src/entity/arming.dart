/// Arming: the subscription table, and the hook that consults it.
///
/// The emission point is git's `reference-transaction` hook rather than
/// `post-commit`, for one concrete reason: `post-commit` fires only for
/// porcelain `git commit`, which has no expected-parent, while an entity's
/// transactions are written with plumbing so the ref update can be a
/// compare-and-swap. `reference-transaction` fires exactly where that swap is
/// decided — and it fires the same way for a ref moved by a push from another
/// site, so one hook covers the local case and the federated one.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'git_entity.dart';

/// What a subscriber is handed, as environment, when it is woken.
///
/// - `BENTOS_ENTITY` — the entity's directory.
/// - `BENTOS_REF` — the ref that moved.
/// - `BENTOS_OLD` / `BENTOS_NEW` — the transaction, as it was and as it is.
const String hookScript = r'''#!/bin/sh
# The emission point. Consults the subscription table and returns: fan-out is a
# table, never a motor, and the commit is never held hostage to the chain — so
# every subscriber is spawned detached, its output going to the wake log.
[ "$1" = "committed" ] || exit 0

entity=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
arming="$entity/.git/bentos"
table="$arming/subscribers"
[ -f "$table" ] || exit 0

while read -r old new ref; do
  case "$ref" in
    refs/heads/*) ;;
    *) continue ;;
  esac
  # A no-op transaction is not an occurrence — this is what keeps a worktree
  # materialization, or any ref rewritten to its own value, from waking anyone.
  [ "$old" = "$new" ] && continue
  while IFS= read -r command || [ -n "$command" ]; do
    case "$command" in
      ''|\#*) continue ;;
    esac
    BENTOS_ENTITY="$entity" BENTOS_REF="$ref" BENTOS_OLD="$old" BENTOS_NEW="$new" \
      sh -c "$command" </dev/null >>"$arming/wake.log" 2>&1 &
  done < "$table"
done
exit 0
''';

/// The subscription table of one entity — behaviours armed at its refs.
///
/// A subscriber is a command line. What divides a monitor from a runner is what
/// the command does, never how it was armed: the table is uniform, which is
/// what lets a drawing be rewired without touching any actor.
final class Arming {
  Arming(this.entity);

  final GitEntity entity;

  File get table => File(p.join(entity.armingDir.path, 'subscribers'));

  /// Where a woken subscriber's output lands. A detached body has nowhere else
  /// to speak, and a dead runner is otherwise a silence.
  File get wakeLog => File(p.join(entity.armingDir.path, 'wake.log'));

  /// Installs the hook. Idempotent — the script is rewritten as it stands here,
  /// which is how an entity created by an older build is brought current.
  void install() {
    entity.armingDir.createSync(recursive: true);
    final hook = File(p.join(entity.gitDir.path, 'hooks', 'reference-transaction'));
    hook.parent.createSync(recursive: true);
    hook.writeAsStringSync(hookScript);
    Process.runSync('chmod', ['+x', hook.path]);
  }

  /// Arms one behaviour. `$BENTOS_*` in [command] is expanded by the shell at
  /// wake time, so a table entry is written once and serves every transaction.
  void subscribe(String command) {
    install();
    final current = subscribers;
    if (current.contains(command)) return;
    table.writeAsStringSync('$command\n', mode: FileMode.append);
  }

  List<String> get subscribers {
    if (!table.existsSync()) return const [];
    return [
      for (final line in table.readAsLinesSync())
        if (line.trim().isNotEmpty && !line.trimLeft().startsWith('#')) line,
    ];
  }
}
