import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:bentos_userland/src/entity/arming/arming.dart';
import 'package:bentos_userland/src/git/process_git.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers.dart';

/// **`Entity.listen`, `Entity.deliveries`, and the `emit` CLI verb.**
///
/// Everything here runs against the real substrate. `Journal.tail` and
/// `Journal.deliveries` are proven file-local in `journal_contract_test.dart`
/// with no Git anywhere near them — correct, since the journal is a file and
/// nothing here doubts that suite. What is new is the seam these two methods
/// and this one verb add: a real transaction producing the occurrences
/// `Entity.listen` reads, a real armed body producing the delivery
/// `Entity.deliveries` reads, and a real hook invoking `entity emit` as a
/// subprocess rather than as a Dart call. Per the fixture audit, a claim about
/// the substrate misbehaving is asserted against the substrate — none of these
/// three is a vocabulary claim a double could carry honestly.
void main() {
  const git = ProcessGit();

  late Directory site;
  late Entity entity;
  late String gitDir;

  setUp(() {
    site = _place('entity_subscribing');
    entity = Entity('bentos.llm', from: site.path).create(actor: testActor);
    gitDir = repositoryOf(site.path, entity.name);
    // Every test below drives dispatch through its own explicit call — the
    // shipped shim would double-fire otherwise.
    File(p.join(gitDir, ArmingTables.hookPath)).deleteSync();
  });

  tearDown(() async {
    for (var attempt = 0; site.existsSync() && attempt < 40; attempt++) {
      try {
        site.deleteSync(recursive: true);
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  });

  Commit born(String id) {
    git.branch(gitDir, name: id, startPoint: entity.genesis);
    return entity.genesis;
  }

  Commit commit(Map<String, String> files, {required Commit parent, String noun = 'prompt'}) {
    final work = Directory('${site.path}/stage');
    if (work.existsSync()) work.deleteSync(recursive: true);
    work.createSync(recursive: true);
    for (final entry in files.entries) {
      File('${work.path}/${entry.key}')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(entry.value);
    }
    return Commit(git.commitTree(
      gitDir,
      tree: git.writeTree(gitDir, workTree: work.path),
      parents: [parent.sha],
      message: Action.messageFor(noun),
      actor: Actor('alfred', email: 'alfred@test.local'),
    ));
  }

  TransactionRefUpdate moving(String id, {required Commit from, required Commit to}) =>
      TransactionRefUpdate(old: from, commit: to, ref: 'refs/heads/$id');

  String body(String name, String script) {
    final file = File('${site.path}/$name.sh')
      ..writeAsStringSync('#!/usr/bin/env bash\nset -uo pipefail\n$script\n');
    Process.runSync('chmod', ['755', file.path]);
    return file.path;
  }

  // --------------------------------------------------------------------
  group('Entity.listen', () {
    test('sees an occurrence from a real transaction, on an unarmed installation',
        () async {
      expect(entity.listeners, isEmpty);
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);

      final stream = entity
          .listen({EventPattern.parse('prompt.landed')}, since: null)
          .take(1)
          .toList();

      await entity.emit(EventPhase.landed, [moving('demo', from: tip, to: next)]);

      final seen = await stream.timeout(const Duration(seconds: 5));
      expect(seen.single.commit.sha, next.sha);
      expect(seen.single.instance.id, 'demo');
    });

    test('a cursor the journal does not hold raises JournalGap', () async {
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);
      await entity.emit(EventPhase.landed, [moving('demo', from: tip, to: next)]);

      expect(
        entity.listen({EventPattern.parse('*.landed')}, since: const Commit('forgotten')),
        emitsError(isA<JournalGap>()),
      );
    });

    test('a killed subprocess terminates and leaves no durable trace',
        () async {
      final tip = born('demo');
      commit({'a': '1'}, parent: tip);

      // **`dart run` and not `entity.dart` directly.** `dart run` splits into
      // a launcher and a worker process, and under piped stdio (what
      // `Process.start` gives a child by default) SIGINT sent to the launcher
      // does not reliably forward — verified directly, against a trivial
      // program with nothing but a signal handler in it: a shell `kill -INT`
      // on a `dart run` job started from an interactive shell is caught
      // cleanly, the identical signal sent to a `Process.start`-spawned one is
      // not, and the same program compiled to an executable catches it either
      // way. That is a fact about the launcher, not about this verb, so the
      // witness is the compiled binary — the shape a shipped `entity` is
      // actually run as.
      final compiled = await _compiledEntityBinary();
      final process = await Process.start(
        compiled,
        ['-C', site.path, 'listen', entity.name, 'prompt.landed'],
      );
      final stdoutLines = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream();

      // Readiness is observed, never guessed: a real occurrence is landed
      // and the test waits for the child to print it. By the time that line
      // arrives the child has subscribed *and* installed its SIGINT handler
      // — `ListenCommand.run` sets up both, back to back, before it ever
      // awaits — so a stdout line is proof the handler is live, which a
      // fixed sleep could only ever assume and lose under load.
      //
      // `listen` now starts at the journal's live tip, not its top, so a
      // single emit racing the child's own startup can land before the child
      // has subscribed and be missed. The retry keeps landing occurrences
      // until one is seen, rather than guessing a delay long enough to win
      // the race once.
      var readyTip = born('ready');
      var caught = false;
      for (var attempt = 0; !caught && attempt < 20; attempt++) {
        final next = commit({'r': '$attempt'}, parent: readyTip);
        await entity.emit(EventPhase.landed, [moving('ready', from: readyTip, to: next)]);
        readyTip = next;
        try {
          await stdoutLines.first.timeout(const Duration(milliseconds: 500));
          caught = true;
        } on TimeoutException {
          // Not yet subscribed — land another and try again.
        }
      }
      expect(caught, isTrue, reason: 'the child never showed as listening');

      // `Process.kill` from a Dart parent does not reliably deliver either,
      // for the same reason — shelling out to `kill` is what actually
      // exercises the claim under test rather than a transport quirk.
      final killed = await Process.run('kill', ['-INT', '${process.pid}']);
      expect(killed.exitCode, 0);

      final code = await process.exitCode.timeout(const Duration(seconds: 10));
      expect(code, 0,
          reason: 'SIGINT closes the stream cleanly rather than leaving a bare '
              'kill to do it — the process is the whole of this reader\'s '
              'lifetime, and it must end when told to');
      expect(entity.listeners, isEmpty,
          reason: 'listen never writes a line, a table entry, or anything '
              'else that outlives the call — unlike `on`, nothing here is '
              'durable to begin with');
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  // --------------------------------------------------------------------
  group('Entity.deliveries', () {
    test('a real armed body that fails is legible through it', () async {
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);
      final armed = entity.on({EventPattern.parse('prompt.landed')},
          command: [body('fails', 'echo "could not reach the model" >&2; exit 4')]);

      await entity.emit(EventPhase.landed, [moving('demo', from: tip, to: next)]);
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (entity.deliveries({EventPattern.parse('prompt.landed')}).isEmpty &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }

      final line = entity.deliveries({EventPattern.parse('prompt.landed')}).single;
      expect(line.subscriber, armed.id);
      expect(line.exitCode, 4);
      expect(line.output, contains('could not reach the model'));
    });
  });

  // --------------------------------------------------------------------
  group('entity emit — the CLI verb a real hook calls', () {
    // The claim no in-process assertion reaches: that the shim's own contract
    // (phase in argv, triples on stdin, exit code as the whole answer) is
    // honoured by the compiled verb and not only by `Entity.emit` called
    // directly from Dart.

    test('a real hook invoking `entity emit` refuses and aborts the update',
        () async {
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);

      entity.on({EventPattern.parse('prompt.attempted')},
          command: [body('gate', "echo \"'\$BENTOS_NOUN' is illegal here\" >&2; exit 1")]);
      _installEmitHook(gitDir, site.path, entity.name);

      final swap = git.updateRef(gitDir,
          ref: 'refs/heads/demo', newCommit: next, expected: tip);

      expect(swap.moved, isFalse,
          reason: 'the CLI verb\'s own exit code is what Git reads at prepared');
      expect(git.revParse(gitDir, 'refs/heads/demo'), tip);
      expect(swap.report, contains("'prompt' is illegal here"));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a real hook invoking `entity emit` lands and wakes what is armed',
        () async {
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);
      final woken = File('${site.path}/woken');

      entity.on({EventPattern.parse('prompt.landed')},
          command: [body('reactor', 'echo "\$BENTOS_COORD" > "${woken.path}"')]);
      _installEmitHook(gitDir, site.path, entity.name);

      expect(
        git
            .updateRef(gitDir,
                ref: 'refs/heads/demo', newCommit: next, expected: tip)
            .moved,
        isTrue,
      );

      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (!woken.existsSync() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(woken.readAsStringSync().trim(), 'bentos.llm:demo');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}

// ---------------------------------------------------------------------------

/// The `entity` coreutil, compiled once and reused by every test that needs
/// it: compiling costs over a second, and the only claim that needs a real
/// binary is signal delivery under piped stdio.
String? _compiledEntityPath;
Future<String> _compiledEntityBinary() async {
  final cached = _compiledEntityPath;
  if (cached != null) return cached;
  final output = p.join(
      Directory.systemTemp.createTempSync('entity_bin').path, 'entity');
  final result = await Process.run(
    Platform.resolvedExecutable,
    ['compile', 'exe', p.join(Directory.current.path, 'bin', 'entity.dart'), '-o', output],
  );
  if (result.exitCode != 0) {
    fail('could not compile entity for the process-boundary test: ${result.stderr}');
  }
  return _compiledEntityPath = output;
}

Directory _place(String label) {
  final root = Directory(
      Directory.systemTemp.createTempSync(label).resolveSymbolicLinksSync());
  Directory('${root.path}/.place').createSync(recursive: true);
  File('${root.path}/.place/place.yaml').writeAsStringSync('name: $label\n');
  return root;
}

/// A `reference-transaction` hook that calls the compiled `entity emit` verb
/// itself, over a real subprocess — never `Entity.emit` reached from Dart, and
/// never the shipped shim, which is a separate delivery with its own gates.
/// This proves the verb's own argv-and-stdin contract, the one thing the
/// in-process groups above cannot reach.
void _installEmitHook(String gitDir, String placePath, String name) {
  final packages =
      p.join(Directory.current.path, '.dart_tool', 'package_config.json');
  final entrypoint = p.join(Directory.current.path, 'bin', 'entity.dart');
  final hook = File(p.join(gitDir, ArmingTables.hookPath))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
#!/usr/bin/env bash
# TEST FIXTURE. Calls the real `entity emit` verb as a subprocess.
exec dart run --packages='$packages' '$entrypoint' -C '$placePath' emit '$name' "\$1"
''');
  Process.runSync('chmod', ['755', hook.path]);
}
