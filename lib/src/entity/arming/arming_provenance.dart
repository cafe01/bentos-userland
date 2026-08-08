/// Replacement by provenance — the arming tables' new member.
///
/// **Declaration only.** The body throws [UnimplementedError]: this is the
/// design chair's contract in literal Dart, landed so the suite compiles and
/// fails naming its own missing member.
///
/// It lives beside the tables and not on the public surface because the plot's
/// layout is this component's alone, exactly as [ArmingTables] itself is: the
/// manifest-line replacement R2.4 requires is the table's member and never a
/// caller's loop.
library;

import '../event.dart';
import 'arming.dart';

/// One line a caller asks to be armed, before an id exists for it.
///
/// A request and not a [Registration]: ids are minted where lines are written,
/// so a caller that had to supply one would be reaching into the table's own
/// business to do it.
final class Arming {
  const Arming({
    required this.instance,
    required this.pattern,
    required this.command,
    this.once = false,
  });

  final String instance;
  final EventPattern pattern;
  final List<String> command;
  final bool once;
}

extension ArmingProvenance on ArmingTables {
  /// Every line of [provenance] is removed and [declared] armed in its place —
  /// **one rewrite per table**, never a remove pass followed by an add pass.
  ///
  /// Lines of any other provenance are untouched, and their order is preserved.
  /// The returned registrations are the newly minted ones, in the order given.
  ///
  /// Idempotent by construction: applying the same [declared] twice leaves
  /// exactly one line per element, which is the whole of R4.1.
  ///
  /// Every command in [declared] passes [ArmingTables.checkCommand] before any
  /// table is rewritten; a refusal leaves every table exactly as it stood. A
  /// table holding no line of [provenance] and receiving no [declared] element
  /// for its phase is not created and not touched. The rewrite is atomic per
  /// table: a reader sees the old set of that provenance or the new one, never
  /// neither.
  List<Registration> replaceProvenance(
    Provenance provenance, {
    required Iterable<Arming> declared,
  }) {
    throw UnimplementedError('ArmingTables.replaceProvenance');
  }
}
