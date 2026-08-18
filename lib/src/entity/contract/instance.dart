/// `instance` — the object everyone touches: existence, birth, the title,
/// reads at a point and as of an instant.
///
/// One type, several pages: [Instance] is composed from the slice each
/// component owns, and every member is declared exactly once, on its owner —
/// [InstanceExistence] here, [InstanceActs] in `action.dart`,
/// [InstanceStanding] in `standing.dart`, [InstanceFunctions] in
/// `function.dart`.
library;

import 'action.dart';
import 'function.dart';
import 'spine.dart';
import 'standing.dart';

/// The whole of an instance, taken together.
abstract interface class Instance
    implements
        InstanceExistence,
        InstanceActs,
        InstanceStanding,
        InstanceFunctions {}

/// The slice this component owns.
abstract interface class InstanceExistence {
  /// The instance's identity: stable for its whole life, never displayed,
  /// and the only thing another primitive may build an address on. The
  /// place's uniform address is `<line root>/<thing>/<identity>` and it must
  /// not move when a title changes.
  String get id;

  /// The title a desk shows, from the newest landing that carries one, or the
  /// manifest's fallback (R2.1.5). Mutable by any landing, and answered with
  /// no content held.
  String get title;

  /// How this instance came to exist, legible forever on every copy that
  /// knows it (R2.1.6). Throws [StateError] on a handle to an unborn instance.
  Birth get birth;

  /// This copy's position, or null when the copy knows the instance exists
  /// but holds no landing of it.
  Point? get here;

  /// Where the instance stood at each source, as of the last contact.
  Map<String, Point> get atSources;

  /// Born from the class's genesis, or forked from [from] (R2.2.1). Dated and
  /// signed like any action.
  Future<Instance> born({required Actor by, Point? from, String? title});

  /// The complete ordered record of everything that happened to it (R2.3.3).
  List<Action> history({Point? since});

  /// The state as of [at], as files, without making the instance present and
  /// without moving where it stands (R2.2.2).
  ///
  /// Throws [ContentUnavailable] when the content was never held here and no
  /// source that holds it can be reached (R2.1.3), naming the sources tried.
  Future<StateView> read({required Point at});

  /// The point this instance stood at as of the wall-clock instant [when],
  /// by the dates the landings carry and never the dates they arrived
  /// (R2.2.3). Null if it did not exist then.
  Point? pointAsOf(Instant when);
}

sealed class Birth {
  const Birth({required this.when, required this.by});
  final Instant when;
  final Actor by;
}

final class FromGenesis extends Birth {
  const FromGenesis({required super.when, required super.by});
}

final class ForkedFrom extends Birth {
  const ForkedFrom({
    required super.when,
    required super.by,
    required this.instance,
    required this.at,
  });
  final String instance;
  final Point at;
}

/// Files at one point, read without a worktree (R2.2.2). A read, never a
/// materialization: it moves nothing and makes nothing present.
abstract interface class StateView {
  List<String> list(String path);
  Future<List<int>> read(String path);
}

final class ContentUnavailable implements Exception {
  const ContentUnavailable(this.instance, {required this.tried});
  final String instance;
  final List<String> tried;
}
