import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../git/model/commit.dart';
import 'entity.dart';
import 'event.dart';
import 'journal.dart';

/// **The deliverer** — how a body is woken, and what is written down about it.
///
/// One occurrence crossed with one matching line: everything needed to start the
/// body and to journal its answer, and nothing that has to be re-derived at the
/// far end. It crosses a process boundary as JSON, because at `.landed` the body
/// is run by a process `Entity.emit` starts and does not wait for.
///
/// > **`.landed` is detached *and* its outcome is journaled. Both, via a
/// > deliverer.** Writing an exit code means waiting for the body; being
/// > detached means not waiting. So `emit` starts a deliverer detached, and the
/// > deliverer starts the body **ordinarily** and waits for it. Detachment
/// > belongs to the deliverer and never to the body — invert the two and the
/// > outcome is unknowable again, which is today's silence with an extra process
/// > in it. The alternatives both drop a proven property: waiting at `.landed`
/// > makes every act pay for the slowest reactor armed on it, and a nullable
/// > exit code preserves the silence in exactly the population that motivated
/// > closing it.
final class Delivery {
  const Delivery({
    required this.gitDir,
    required this.place,
    required this.entity,
    required this.subscriber,
    required this.command,
    required this.ref,
    required this.instance,
    required this.noun,
    required this.phase,
    required this.commit,
    required this.parent,
    required this.environment,
  });

  final String gitDir;
  final String place;
  final String entity;

  /// The `Registration.id` that matched.
  final String subscriber;

  /// The armed command line, as argv. The occurrence is appended to it.
  final List<String> command;

  final String ref;
  final String instance;
  final String noun;
  final EventPhase phase;
  final Commit commit;
  final Commit parent;

  /// The occurrence as environment — the nine names of the event page, decided
  /// by dispatch. Composed here with the parent environment rather than carried
  /// whole, so a payload stays a line rather than a copy of a process's world.
  final Map<String, String> environment;

  Map<String, Object?> toJson() => {
        'gitDir': gitDir,
        'place': place,
        'entity': entity,
        'subscriber': subscriber,
        'command': command,
        'ref': ref,
        'instance': instance,
        'noun': noun,
        'phase': phase.suffix,
        'commit': commit.sha,
        'parent': parent.sha,
        'environment': environment,
      };

  factory Delivery.fromJson(Map<String, Object?> json) => Delivery(
        gitDir: json['gitDir']! as String,
        place: json['place']! as String,
        entity: json['entity']! as String,
        subscriber: json['subscriber']! as String,
        command: [for (final word in json['command']! as List) word as String],
        ref: json['ref']! as String,
        instance: json['instance']! as String,
        noun: json['noun']! as String,
        phase: EventPhase.values.firstWhere((p) => p.suffix == json['phase']),
        commit: Commit(json['commit']! as String),
        parent: Commit(json['parent']! as String),
        environment: {
          for (final e in (json['environment']! as Map).entries)
            e.key as String: e.value as String,
        },
      );

  /// The occurrence this delivery belongs to, rebuilt at the far end. The
  /// handles are lazy, so this touches no disk.
  Event get event => Event(
        instance: Entity(entity, from: place).instance(instance),
        noun: noun,
        phase: phase,
        commit: commit,
        parent: parent,
      );
}

/// The variables a ref transaction exports, and which must not survive into
/// anything dispatch wakes.
///
/// A body that inherited `GIT_DIR` would run its own `git` against the
/// transaction's repository rather than its own; one that inherited a quarantine
/// would read a store that is about to vanish. Dart cannot unset a variable, so
/// the environment a child gets is composed here and handed over whole, with
/// `includeParentEnvironment: false`.
///
/// The same list the Git port scrubs on its own invocations. It is written twice
/// because the port's copy is private to it and this one is about the bodies we
/// wake rather than about the port's own children — a platform fact with two
/// homes, and owed one.
const List<String> transactionEnvironment = [
  'GIT_DIR',
  'GIT_WORK_TREE',
  'GIT_INDEX_FILE',
  'GIT_OBJECT_DIRECTORY',
  'GIT_QUARANTINE_PATH',
  'GIT_ALTERNATE_OBJECT_DIRECTORIES',
  'GIT_COMMON_DIR',
  'GIT_PREFIX',
];

/// This process's environment with a transaction's own stripped out.
Map<String, String> withoutTransactionEnvironment() => {
      for (final e in Platform.environment.entries)
        if (!transactionEnvironment.contains(e.key)) e.key: e.value,
    };

/// Runs the body and answers with the line that records it — the one
/// implementation of *waking something*, used in line by a held gate and by the
/// deliverer at every other phase.
///
/// The body is called with the occurrence appended to its own argv —
/// `gitDir ref old new noun` — and with the occurrence in its environment. The
/// argv contract is the retired shim's, unchanged, so a body armed before the
/// trampoline keeps working after it; the environment is what a body reached
/// through `entity run` needs, argv not surviving that hop.
///
/// **It journals unconditionally, including a body that could not be executed at
/// all.** Recording only the executions that happened would reintroduce silence
/// at the one place this design closes it, and *not found* is the commonest way
/// an armed line dies.
Future<DeliveryLine> perform(Delivery delivery) async {
  final argv = [
    ...delivery.command.skip(1),
    delivery.gitDir,
    delivery.ref,
    delivery.parent.sha,
    delivery.commit.sha,
    delivery.noun,
  ];
  int code;
  String output;
  try {
    final result = await Process.run(
      delivery.command.first,
      argv,
      environment: {
        ...withoutTransactionEnvironment(),
        ...delivery.environment,
      },
      includeParentEnvironment: false,
      stdoutEncoding: null,
      stderrEncoding: null,
    );
    code = result.exitCode;
    output = _text(result.stdout) + _text(result.stderr);
  } on ProcessException catch (e) {
    // The substrate's own account, carried. A missing line here would be the
    // failure mode with the loudest cause and the quietest record.
    code = _couldNotExecute;
    output = '${e.message}: ${e.executable}\n';
  }
  return DeliveryLine(
    entity: delivery.entity,
    event: delivery.event,
    subscriber: delivery.subscriber,
    command: delivery.command,
    exitCode: code,
    output: output,
  );
}

/// What is recorded when the body never ran — the shell's own number for a
/// command it could not execute, so a reader of the journal is not learning a
/// second vocabulary.
const int _couldNotExecute = 127;

/// Starts a deliverer for [delivery], detached, and returns the moment it is
/// started. The landing is never held hostage to what it wakes.
Future<void> detach(Delivery delivery) async {
  final command = await delivererCommand(jsonEncode(delivery.toJson()));
  await Process.start(
    command.first,
    command.sublist(1),
    mode: ProcessStartMode.detached,
    environment: withoutTransactionEnvironment(),
    includeParentEnvironment: false,
  );
}

/// The hidden verb the shipped executable answers a deliverer payload on. Not a
/// command of the coreutil: it takes no options, appears in no usage, and is
/// produced by nothing except [detach].
const String delivererVerb = '__deliver';

/// This library, named as a package uri — how a deliverer is found when the code
/// is running from source.
const String delivererLibrary =
    'package:bentos_userland/src/entity/deliverer.dart';

/// The command that starts a deliverer, given where this process's own code
/// stands.
///
/// **Two modes, and the branch is on how this process was built.** Running from
/// source — a developer, and every test in this package — [source] resolves to
/// this file on disk and the deliverer is the Dart runtime running it, which
/// needs nothing installed anywhere. Compiled, package resolution answers
/// nothing, and the deliverer is **this executable re-exec'd** on the hidden
/// verb: dispatch is reached through the shim, which execs `entity`, so
/// [Platform.resolvedExecutable] is that binary.
List<String> delivererCommandFrom({
  required String executable,
  required String? source,
  required String payload,
}) =>
    source == null
        ? [executable, delivererVerb, payload]
        : [executable, 'run', source, payload];

Future<List<String>> delivererCommand(String payload) async =>
    delivererCommandFrom(
      executable: Platform.resolvedExecutable,
      source: await delivererSource(),
      payload: payload,
    );

/// This file's path when the code is running from source, and null when it is
/// not — package resolution being exactly the thing a compiled executable does
/// not carry.
Future<String?> delivererSource() async {
  try {
    final resolved = await Isolate.resolvePackageUri(Uri.parse(delivererLibrary));
    if (resolved == null || !resolved.isScheme('file')) return null;
    final path = resolved.toFilePath();
    return File(path).existsSync() ? path : null;
  } on Object {
    return null;
  }
}

String _text(Object? raw) =>
    raw is List<int> ? utf8.decode(raw, allowMalformed: true) : '$raw';

/// The deliverer's own turn: run the body, wait for it, write the line.
Future<void> deliver(String payload) async {
  final delivery =
      Delivery.fromJson(jsonDecode(payload) as Map<String, Object?>);
  Journal(delivery.gitDir, Entity(delivery.entity, from: delivery.place))
      .appendDelivery(await perform(delivery));
}

/// The entry point in **source** mode — this file run by the Dart runtime. The
/// compiled mode's entry point is the shipped executable's own front door,
/// which recognises [delivererVerb] and calls [deliver].
Future<void> main(List<String> argv) async {
  if (argv.length != 1) {
    stderr.writeln('deliverer: one payload argument');
    exit(64);
  }
  await deliver(argv.single);
}
