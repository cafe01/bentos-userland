/// The collaborator: the entity primitive, as the face reaches it.
///
/// This interface is the whole of what the face is allowed to know about the
/// floor. It names the primitive's verbs and nothing else — no repository, no
/// worktree, no path under `.place`, no function resolved by hand, no manifest
/// read, no environment laid. **Reaching beneath this line is the one thing a
/// face never does**, which is also why deleting a conversation is not a verb:
/// the primitive does not kill an instance, and a face that did would be
/// reaching under the interface it stands on.
///
/// It is an interface so the suite can put a double here. The double answers the
/// same claims the machine does; where it cannot, the gate says so rather than
/// asserting against a friendlier world.
library;

import 'coordinate.dart';

/// A commit. Every screen is pinned to one of these.
extension type const Sha(String value) {}

/// One instance of a class, as `entity ls <name>` hands it back.
final class InstanceRef {
  const InstanceRef(this.instance, this.tip);

  final String instance;

  /// Null when the instance exists in the listing but stands at no commit.
  final Sha? tip;
}

/// One act, as the log describes it. The sentence is the only field with no
/// fixed shape, and it is the last one for that reason.
final class Act {
  const Act({
    required this.sha,
    required this.name,
    required this.actor,
    required this.instant,
    this.sentence,
  });

  final Sha sha;
  final String name;
  final String actor;
  final DateTime instant;

  /// Null when the act said nothing, which is a different fact from an empty
  /// sentence.
  final String? sentence;
}

/// What a captured call to a function returned.
final class RunOutcome {
  const RunOutcome({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// The primitive refused, or could not answer. The face never translates this
/// into a guess about the tree.
final class PrimitiveFailure implements Exception {
  const PrimitiveFailure(this.verb, this.message, {this.exitCode});

  final String verb;
  final String message;
  final int? exitCode;
}

/// The verbs of `entity` that the face speaks.
abstract interface class Primitive {
  /// The commit the instance stands at, or null when it has not been born.
  Future<Sha?> tip(Coordinate coord, {Vantage vantage = const Vantage.here()});

  /// The instances of a class. Genesis is not one of them.
  Future<List<InstanceRef>> instances(String entity, {Vantage vantage = const Vantage.here()});

  /// The paths one level under [path] in that instance's tree, at a point in
  /// history.
  Future<List<String>> ls(
    Coordinate coord,
    String path, {
    Sha? asOf,
    Vantage vantage = const Vantage.here(),
  });

  /// The bytes at one path, at a point in history.
  Future<String> read(
    Coordinate coord,
    String path, {
    Sha? asOf,
    Vantage vantage = const Vantage.here(),
  });

  /// The acts, newest last.
  Future<List<Act>> log(Coordinate coord, {Vantage vantage = const Vantage.here()});

  /// Birth an instance — from genesis, or from a live commit, which is a fork.
  /// One operation and two origins, exactly as the primitive has it.
  Future<Sha> birth(Coordinate coord, {Sha? from, Vantage vantage = const Vantage.here()});

  /// Run a declared function at a coordinate, captured. The face names a verb
  /// and never a layout.
  Future<RunOutcome> run(
    Coordinate coord,
    String function,
    List<String> arguments, {
    Vantage vantage = const Vantage.here(),
  });

  /// The same, with the caller's own streams — for a body that writes to the
  /// terminal for as long as it lives, which is what the live register is.
  Future<int> attach(
    Coordinate coord,
    String function,
    List<String> arguments, {
    Vantage vantage = const Vantage.here(),
  });
}
