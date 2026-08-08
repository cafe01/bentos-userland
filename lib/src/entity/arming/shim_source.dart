/// The `reference-transaction` shim — the trampoline into the primitive, and
/// the one part of this package that is not Dart.
///
/// # Why shell, and why only this much of it
///
/// The hook fires on **every ref update** — every action, and every ref of
/// every push — so a VM start on that path is paid on all of them, and Dart
/// never runs here. But matching, lifetimes, provenance, detaching and
/// journaling are not shell's to carry a second time: they live once, in
/// [Dispatch.emit], reached through `entity emit`. What survives here is the
/// two facts that cannot move into that call — the contract with Git, and
/// self-location — six lines against what was a hundred and fifty.
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
/// detached. The mapping is `emit`'s first line, not the shim's: the shim
/// forwards Git's own word on argv[1] verbatim.
///
/// # A publisher that cannot reach the primitive refuses
///
/// `exec` replaces the shell with `entity`, so stdin — the transaction's own
/// triples — passes through untouched and the exit code Git reads is
/// `entity`'s, not bash's. An unresolvable `entity` fails this line as any
/// other unresolvable command does: non-zero, non-`exec`'d, and Git aborts at
/// `prepared` on that alone. Silent admission is the failure this design
/// treats: an act nobody could validate must not land.
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
# reference-transaction — publishes into the primitive. Generated; do not edit.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
exec entity -C "$REPO" emit '__BENTOS_ENTITY__' "$1"
''';
