/// The doubles: one per collaborator the contract declares.
///
/// **A double answers claims; it does not re-implement the floor.** This fake
/// primitive holds trees and hands back what it was given — it does not know
/// what `user.say` means, and a test that needs a function to behave scripts it.
/// A fake that reimplemented the entity would be a second implementation of the
/// machine, and green against it would say only that our two guesses agree.
///
/// Every double records what it was asked, because several claims of this
/// contract are about *how* the face asked: one tip per screen, the same commit
/// carried into every read, no wait after a refusal.
library;

import 'package:bentos_userland/src/llm/session/coordinate.dart';
import 'package:bentos_userland/src/llm/session/machine.dart';
import 'package:bentos_userland/src/llm/session/primitive.dart';
import 'package:bentos_userland/src/llm/session/transcript.dart';
import 'package:bentos_userland/src/llm/session/turn.dart';

/// One thing the face asked the floor for.
final class PrimitiveCall {
  const PrimitiveCall(this.verb, {this.coord, this.argument, this.asOf});

  final String verb;
  final String? coord;
  final String? argument;
  final Sha? asOf;

  @override
  String toString() => '$verb($coord, $argument, asOf: ${asOf?.value})';
}

/// A world of trees at commits, plus a ledger of everything asked of it.
final class FakePrimitive implements Primitive {
  FakePrimitive();

  /// sha → (path → contents).
  final Map<String, Map<String, String>> trees = {};

  /// `<entity>:<instance>` → the commit it stands at.
  final Map<String, Sha?> tips = {};

  /// `<entity>:<instance>` → its acts, oldest first.
  final Map<String, List<Act>> logs = {};

  /// Scripted functions: name → what running it does. A function nobody scripted
  /// fails loudly rather than returning a friendly zero.
  final Map<String, RunOutcome Function(List<String> arguments)> functions = {};

  /// Ran after every read, so a test can make the world move *between* the reads
  /// of one screen — the witness for the pinning law.
  void Function()? afterEachRead;

  /// The order `ls` hands paths back in. The primitive promises names that sort
  /// into chronology, not a listing already sorted, so a reader that leaned on
  /// the listing's order has to be caught here.
  List<String> Function(List<String> sorted)? lsOrder;

  final List<PrimitiveCall> calls = [];

  List<PrimitiveCall> callsTo(String verb) =>
      calls.where((c) => c.verb == verb).toList();

  String key(Coordinate coord) => '${coord.entity}:${coord.instance}';

  /// Lay a commit down. The contents are whatever the caller gives — bytes from
  /// a real session, ideally, and never bytes this package produced.
  void commit(Coordinate coord, Sha sha, Map<String, String> tree) {
    trees[sha.value] = tree;
    tips[key(coord)] = sha;
  }

  Map<String, String> _treeAt(Coordinate coord, Sha? asOf) {
    final sha = asOf ?? tips[key(coord)];
    if (sha == null) throw PrimitiveFailure('read', 'not born: ${key(coord)}');
    final tree = trees[sha.value];
    if (tree == null) {
      throw PrimitiveFailure('read', 'no such commit: ${sha.value}');
    }
    return tree;
  }

  @override
  Future<Sha?> tip(Coordinate coord, {Vantage vantage = const Vantage.here()}) async {
    calls.add(PrimitiveCall('tip', coord: key(coord)));
    return tips[key(coord)];
  }

  @override
  Future<List<InstanceRef>> instances(
    String entity, {
    Vantage vantage = const Vantage.here(),
  }) async {
    calls.add(PrimitiveCall('instances', argument: entity));
    return [
      for (final entry in tips.entries)
        if (entry.key.startsWith('$entity:'))
          InstanceRef(entry.key.split(':').last, entry.value),
    ];
  }

  @override
  Future<List<String>> ls(
    Coordinate coord,
    String path, {
    Sha? asOf,
    Vantage vantage = const Vantage.here(),
  }) async {
    calls.add(
      PrimitiveCall('ls', coord: key(coord), argument: path, asOf: asOf),
    );
    final prefix = path.isEmpty ? '' : '$path/';
    final under = _treeAt(coord, asOf)
        .keys
        .where((p) => p.startsWith(prefix))
        .toList()
      ..sort();
    afterEachRead?.call();
    return lsOrder?.call(under) ?? under;
  }

  @override
  Future<String> read(
    Coordinate coord,
    String path, {
    Sha? asOf,
    Vantage vantage = const Vantage.here(),
  }) async {
    calls.add(
      PrimitiveCall('read', coord: key(coord), argument: path, asOf: asOf),
    );
    final tree = _treeAt(coord, asOf);
    final body = tree[path];
    if (body == null) {
      throw PrimitiveFailure('read', 'no such path: $path');
    }
    afterEachRead?.call();
    return body;
  }

  @override
  Future<List<Act>> log(
    Coordinate coord, {
    Vantage vantage = const Vantage.here(),
  }) async {
    calls.add(PrimitiveCall('log', coord: key(coord)));
    return logs[key(coord)] ?? const [];
  }

  @override
  Future<Sha> birth(
    Coordinate coord, {
    Sha? from,
    Vantage vantage = const Vantage.here(),
  }) async {
    calls.add(PrimitiveCall('birth', coord: key(coord), asOf: from));
    final born = Sha('born-${key(coord)}');
    trees[born.value] = from == null
        ? <String, String>{}
        : Map<String, String>.from(trees[from.value] ?? const {});
    tips[key(coord)] = born;
    return born;
  }

  @override
  Future<RunOutcome> run(
    Coordinate coord,
    String function,
    List<String> arguments, {
    Vantage vantage = const Vantage.here(),
  }) async {
    calls.add(
      PrimitiveCall('run', coord: key(coord), argument: '$function ${arguments.join(' ')}'.trim()),
    );
    final scripted = functions[function];
    if (scripted == null) {
      throw PrimitiveFailure(
        'run',
        'the double was never told what $function does — script it in the test '
            'rather than teaching this fake the entity',
      );
    }
    return scripted(arguments);
  }

  @override
  Future<int> attach(
    Coordinate coord,
    String function,
    List<String> arguments, {
    Vantage vantage = const Vantage.here(),
  }) async {
    calls.add(PrimitiveCall('attach', coord: key(coord), argument: function));
    final scripted = functions[function];
    return scripted == null ? 0 : scripted(arguments).exitCode;
  }
}

/// Where the coordinate came from, scripted.
///
/// The export line is a **sentinel**: no code in the face could invent it, so a
/// `use` that returns it is a `use` that asked the source instead of spelling a
/// variable name of its own.
final class FakeCoordinateSource implements CoordinateSource {
  FakeCoordinateSource({
    this.resolution,
    this.failure,
    this.line = 'export SENTINEL_FROM_THE_FLOOR=nobody-here-could-invent-this',
  });

  CoordinateResolution? resolution;
  Exception? failure;
  String line;

  final List<String?> asked = [];

  @override
  Future<CoordinateResolution> resolve(
    String? spelled, {
    Vantage vantage = const Vantage.here(),
  }) async {
    asked.add(spelled);
    if (failure != null) throw failure!;
    final answer = resolution;
    if (answer == null) throw const CoordinateAbsent();
    return answer;
  }

  @override
  Future<String> exportLine(Coordinate coordinate) async => line;
}

/// The fold, scripted per reading — a list, so a test can make the state move
/// between one call and the next.
final class FakeMachine implements MachineReader {
  FakeMachine(this._folds);

  final List<Fold> _folds;
  final List<Sha?> asOfAsked = [];
  int _next = 0;

  int get foldCount => asOfAsked.length;

  @override
  Future<Fold> fold(
    Coordinate coord, {
    Sha? asOf,
    Vantage vantage = const Vantage.here(),
  }) async {
    asOfAsked.add(asOf);
    final fold = _folds[_next < _folds.length ? _next : _folds.length - 1];
    _next++;
    return fold;
  }
}

/// The transcript, scripted per commit. Reading at a commit nobody laid is an
/// error rather than an empty conversation.
final class FakeTranscripts implements TranscriptReader {
  FakeTranscripts(this.atCommit, {this.atTip = const []});

  final Map<String, List<StoredMessage>> atCommit;
  final List<StoredMessage> atTip;
  final List<Sha?> asOfAsked = [];

  @override
  Future<List<String>> messageNames(
    Coordinate coord, {
    Sha? asOf,
    Vantage vantage = const Vantage.here(),
  }) async {
    asOfAsked.add(asOf);
    return (await transcript(coord, asOf: asOf)).map((m) => m.path).toList();
  }

  @override
  Future<List<StoredMessage>> transcript(
    Coordinate coord, {
    Sha? asOf,
    Vantage vantage = const Vantage.here(),
  }) async {
    asOfAsked.add(asOf);
    if (asOf == null) return atTip;
    final at = atCommit[asOf.value];
    if (at == null) throw PrimitiveFailure('read', 'no such commit: ${asOf.value}');
    return at;
  }
}

/// Waiting, scripted — including *whether it was waited on at all*.
final class FakeRest implements Rest {
  FakeRest(this.outcome);

  TurnOutcome outcome;
  int waits = 0;
  Duration? limitAsked;

  /// Ran while the wait is in flight, so a test can land a reply during it.
  void Function()? during;

  @override
  Future<TurnOutcome> awaitRest(
    Coordinate coord, {
    required Duration limit,
    bool Function()? cancelled,
    Vantage vantage = const Vantage.here(),
  }) async {
    waits++;
    limitAsked = limit;
    during?.call();
    return outcome;
  }
}

/// A `Deposited`-shaped success for a scripted function.
RunOutcome deposited(String sha, {String? sentence}) =>
    RunOutcome(exitCode: 0, stdout: '$sha\n', stderr: sentence ?? '');

/// A refusal from the floor, with the floor's own words.
RunOutcome refused(String message, {int exitCode = 1}) =>
    RunOutcome(exitCode: exitCode, stdout: '', stderr: message);
