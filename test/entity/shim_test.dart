import 'dart:io';

import 'package:bentos_userland/src/entity/arming/shim_source.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// **Tier B — the shim as a process.** Shell and a temp directory: no
/// repository, no Dart in the path under test, no substrate at all.
///
/// The shim is a program with its own contract — phase in argv, `old new ref`
/// on stdin, exit code as its whole answer — and that is exactly why it can be
/// proven here, today, green. It is also the entity's entire nervous system, so
/// leaving it to an integration test would be leaving the load-bearing part
/// unproven the longest.
///
/// `git` itself is stood in for by a script earlier on `PATH`, which keeps the
/// tier honest: the shim really does spawn what it says it spawns.
void main() {
  late Directory tmp;
  late String repo;
  late String actions;

  const zero = '0000000000000000000000000000000000000000';
  const oldSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const newSha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('shim_test');
    // The shim locates the entity as `dirname $0/..`, so it must sit in
    // `<repo>/hooks/` exactly as Git installs it.
    repo = p.join(tmp.path, 'e.git');
    Directory(p.join(repo, 'hooks')).createSync(recursive: true);
    Directory(p.join(repo, 'bentos')).createSync(recursive: true);
    final hook = File(p.join(repo, 'hooks', 'reference-transaction'))
      ..writeAsStringSync(referenceTransactionShimFor('probe.thing'));
    Process.runSync('chmod', ['755', hook.path]);

    // The stand-in for git: answers `cat-file commit <sha>` out of a directory
    // the test writes, and is found before the real one on PATH.
    actions = p.join(tmp.path, 'actions');
    Directory(actions).createSync(recursive: true);
    final bin = Directory(p.join(tmp.path, 'bin'))..createSync(recursive: true);
    final fakeGit = File(p.join(bin.path, 'git'))
      ..writeAsStringSync('''#!/usr/bin/env bash
for last; do :; done
f="\$FAKEGIT_ACTIONS/\$last"
[ -f "\$f" ] && cat "\$f"
exit 0
''');
    Process.runSync('chmod', ['755', fakeGit.path]);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  void declareAction(String sha, String action) {
    File(p.join(actions, sha)).writeAsStringSync(
      'tree deadbeef\n\n$action\n\nBentos-Action: $action\n',
    );
  }

  void arm(String phase, String line) {
    File(p.join(repo, 'bentos', phase)).writeAsStringSync('$line\n');
  }

  /// One table line: `<id>\t<instance>\t<action>\t<lifetime>\t<command…>`.
  String armed(
    String id,
    String instance,
    String action,
    String command, {
    String life = 'always',
  }) =>
      [id, instance, action, life, command].join('\t');

  String tableOf(String phase) =>
      File(p.join(repo, 'bentos', phase)).readAsStringSync();

  /// A listener that records its arguments and answers with [exitCode].
  String listener(String label, {int exitCode = 0}) {
    final script = File(p.join(tmp.path, label))
      ..writeAsStringSync('''#!/usr/bin/env bash
echo "\$@" >> "${p.join(tmp.path, '$label.log')}"
exit $exitCode
''');
    Process.runSync('chmod', ['755', script.path]);
    return script.path;
  }

  /// Fires the shim at [phase] with a transaction's lines on stdin. The lines
  /// are piped by a shell because that is how Git feeds the hook, and because
  /// [Process.runSync] cannot write to a child's stdin.
  ProcessResult fireWith(String phase, List<String> lines) {
    final input = File(p.join(tmp.path, 'stdin'))
      ..writeAsStringSync('${lines.join('\n')}\n');
    return Process.runSync(
      'bash',
      [
        '-c',
        '"${p.join(repo, 'hooks', 'reference-transaction')}" $phase < "${input.path}"',
      ],
      environment: {
        'PATH': '${p.join(tmp.path, 'bin')}:${Platform.environment['PATH']}',
        'FAKEGIT_ACTIONS': actions,
      },
    );
  }

  File logOf(String label) => File(p.join(tmp.path, '$label.log'));

  Future<bool> appears(File file) async {
    for (var i = 0; i < 60; i++) {
      if (file.existsSync()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return false;
  }

  test('an unknown phase is not the shim\'s business', () {
    expect(fireWith('unknown', ['$oldSha $newSha refs/heads/s1']).exitCode, 0);
  });

  test('no table means nothing to do', () {
    declareAction(newSha, 'prompt');
    expect(fireWith('prepared', ['$oldSha $newSha refs/heads/s1']).exitCode, 0);
  });

  group('the attempted phase holds the act', () {
    test('a listener that refuses aborts the transaction', () {
      declareAction(newSha, 'prompt');
      arm('attempted', armed('r1', '*', 'prompt', listener('validator', exitCode: 1)));

      final result = fireWith('prepared', ['$oldSha $newSha refs/heads/s1']);
      expect(result.exitCode, isNot(0), reason: 'a non-zero exit aborts the update');
      expect(result.stderr.toString(), contains('refused by r1'));
    });

    test('a gate\'s own words come back on stderr, and stay in the log', () {
      declareAction(newSha, 'prompt');
      // A gate that says why. Its sentence is the whole of what a person needs,
      // and it is written where every body writes — its own stderr.
      final gate = File(p.join(tmp.path, 'speaking-gate'))
        ..writeAsStringSync('''#!/usr/bin/env bash
echo "check: 'prompt' is illegal at owes_inference" >&2
exit 1
''');
      Process.runSync('chmod', ['755', gate.path]);
      arm('attempted', armed('r1', '*', 'prompt', gate.path));

      final result = fireWith('prepared', ['$oldSha $newSha refs/heads/s1']);
      expect(result.exitCode, isNot(0));
      // Git carries this stream up through `update-ref`, which is the only road
      // the sentence has to whoever typed the act. Without it the refusal reads
      // `refused by r1: <command line>` and sends a person to a log file.
      expect(
        result.stderr.toString(),
        contains("'prompt' is illegal at owes_inference"),
      );
      expect(
        File(p.join(repo, 'bentos', 'reactor.log')).readAsStringSync(),
        contains("'prompt' is illegal at owes_inference"),
        reason: 'the log keeps everything it always kept',
      );
      expect(
        Directory(p.join(repo, 'bentos'))
            .listSync()
            .map((e) => p.basename(e.path)),
        isNot(contains(startsWith('refusal.'))),
        reason: 'the buffer is the shim\'s own, and it does not survive it',
      );
    });

    test('the occurrence carries the parent, not only the new value', () {
      declareAction(newSha, 'prompt');
      // The environment is the only road: a gate reached through `entity run`
      // is a grandchild of this shim, and argv does not survive that hop.
      final scribe = File(p.join(tmp.path, 'scribe'))
        ..writeAsStringSync('''#!/usr/bin/env bash
env | grep '^BENTOS_' | sort > "${p.join(tmp.path, 'env.log')}"
exit 0
''');
      Process.runSync('chmod', ['755', scribe.path]);
      arm('attempted', armed('r1', '*', 'prompt', scribe.path));

      expect(fireWith('prepared', ['$oldSha $newSha refs/heads/s1']).exitCode, 0);
      final env = File(p.join(tmp.path, 'env.log')).readAsStringSync();
      expect(env, contains('BENTOS_OLD=$oldSha'),
          reason: 'a gate judges the act at its PARENT, and this is the parent');
      expect(env, contains('BENTOS_SHA=$newSha'));
      expect(env, isNot(contains('BENTOS_NEW=')),
          reason: 'one value under two names is a drift waiting');
    });

    test('a listener that consents lets it through, and runs in line', () {
      declareAction(newSha, 'prompt');
      arm('attempted', armed('r1', '*', 'prompt', listener('validator')));

      expect(fireWith('prepared', ['$oldSha $newSha refs/heads/s1']).exitCode, 0);
      expect(
        logOf('validator').readAsStringSync().trim(),
        '$repo refs/heads/s1 $oldSha $newSha prompt',
        reason: 'the occurrence is the entity, the ref, both tips and the noun',
      );
    });
  });

  group('the landed phase wakes and forgets', () {
    test('a subscriber is fired detached', () async {
      declareAction(newSha, 'reply');
      arm('landed', armed('r2', '*', 'reply', listener('subscriber')));

      expect(fireWith('committed', ['$oldSha $newSha refs/heads/s1']).exitCode, 0);
      expect(
        await appears(logOf('subscriber')),
        isTrue,
        reason: 'the landing is never held hostage to what it wakes',
      );
    });

    test('a subscriber that fails does not fail the landing', () async {
      declareAction(newSha, 'reply');
      arm('landed', armed('r2', '*', 'reply', listener('bad', exitCode: 9)));
      expect(fireWith('committed', ['$oldSha $newSha refs/heads/s1']).exitCode, 0);
    });
  });

  test('the aborted phase publishes the refusal', () async {
    declareAction(newSha, 'prompt');
    arm('refused', armed('r3', '*', '*', listener('onrefused')));
    expect(fireWith('aborted', ['$oldSha $newSha refs/heads/s1']).exitCode, 0);
    expect(await appears(logOf('onrefused')), isTrue);
  });

  group('what is not an action', () {
    setUp(() {
      declareAction(newSha, 'prompt');
      arm('landed', armed('r', '*', '*', listener('any')));
    });

    test('a birth is not an act', () async {
      expect(fireWith('committed', ['$zero $newSha refs/heads/s1']).exitCode, 0);
      expect(logOf('any').existsSync(), isFalse);
    });

    test('a deletion is not an act', () async {
      expect(fireWith('committed', ['$oldSha $zero refs/heads/s1']).exitCode, 0);
      expect(logOf('any').existsSync(), isFalse);
    });

    test('genesis is the structure, not an instance', () async {
      expect(fireWith('committed', ['$oldSha $newSha refs/heads/genesis']).exitCode, 0);
      expect(logOf('any').existsSync(), isFalse);
    });

    test('a ref that is not an instance is ignored', () async {
      expect(fireWith('committed', ['$oldSha $newSha refs/tags/v1']).exitCode, 0);
      expect(logOf('any').existsSync(), isFalse);
    });

    test('an unchanged ref is nothing at all', () async {
      expect(fireWith('committed', ['$oldSha $oldSha refs/heads/s1']).exitCode, 0);
      expect(logOf('any').existsSync(), isFalse);
    });
  });

  group('selection', () {
    test('an action glob that does not match stays silent', () {
      declareAction(newSha, 'prompt');
      arm('attempted', armed('r', '*', 'reply', listener('v', exitCode: 1)));
      expect(
        fireWith('prepared', ['$oldSha $newSha refs/heads/s1']).exitCode,
        0,
        reason: 'a listener armed on another noun never sees this act',
      );
    });

    test('an instance glob that does not match stays silent', () {
      declareAction(newSha, 'prompt');
      arm('attempted', armed('r', 's2', 'prompt', listener('v', exitCode: 1)));
      expect(fireWith('prepared', ['$oldSha $newSha refs/heads/s1']).exitCode, 0);
    });

    test('a prefix glob selects a family of nouns', () {
      declareAction(newSha, 'tool-result');
      arm('attempted', armed('r', '*', 'tool-*', listener('v', exitCode: 1)));
      expect(fireWith('prepared', ['$oldSha $newSha refs/heads/s1']).exitCode, isNot(0));
    });

    test('a commented line is not a fault', () {
      declareAction(newSha, 'prompt');
      File(p.join(repo, 'bentos', 'attempted')).writeAsStringSync(
        '# disabled for now\n\n${armed('r', '*', 'prompt', listener('v'))}\n',
      );
      expect(fireWith('prepared', ['$oldSha $newSha refs/heads/s1']).exitCode, 0);
      expect(logOf('v').existsSync(), isTrue);
    });
  });

  group('the provenance column', () {
    /// A table line carrying the new column, verbatim: `<id>\t<instance>\t
    /// <action>\t<lifetime>\t<provenance>\t--\t<arg>…`.
    String armedWithProvenance(
      String id,
      String instance,
      String action,
      String provenance,
      List<String> command, {
      String life = 'always',
    }) =>
        [id, instance, action, life, provenance, '--', ...command].join('\t');

    test('all six BENTOS_* reach the listener with the occurrence\'s values',
        () async {
      declareAction(newSha, 'reply');
      final envLog = File(p.join(tmp.path, 'env.log'));
      final scribe = File(p.join(tmp.path, 'scribe'))
        ..writeAsStringSync('''#!/usr/bin/env bash
env | grep '^BENTOS_' | sort > "${envLog.path}"
exit 0
''');
      Process.runSync('chmod', ['755', scribe.path]);
      arm(
        'landed',
        armedWithProvenance('r1', '*', 'reply', 'manifest', [scribe.path]),
      );

      expect(fireWith('committed', ['$oldSha $newSha refs/heads/s1']).exitCode, 0);
      expect(await appears(envLog), isTrue, reason: 'landed listeners are detached');
      final env = envLog.readAsStringSync();
      expect(env, contains('BENTOS_ENTITY=probe.thing'));
      expect(env, contains('BENTOS_PHASE=landed'));
      expect(env, contains('BENTOS_INSTANCE=s1'));
      expect(env, contains('BENTOS_NOUN=reply'));
      expect(env, contains('BENTOS_EVENT=reply.landed'));
      expect(env, contains('BENTOS_SHA=$newSha'));
      expect(env, contains('BENTOS_OLD=$oldSha'));
    });

    test('a line with a provenance column dispatches with the right command',
        () {
      declareAction(newSha, 'prompt');
      arm(
        'attempted',
        armedWithProvenance(
          'r1',
          '*',
          'prompt',
          'manifest',
          [listener('v'), '--flag', 'two words'],
        ),
      );

      expect(fireWith('prepared', ['$oldSha $newSha refs/heads/s1']).exitCode, 0);
      // The provenance word and the sentinel are read and consumed — neither
      // reaches the listener, and the argument holding a space survives whole.
      expect(
        logOf('v').readAsStringSync().trim(),
        '--flag two words $repo refs/heads/s1 $oldSha $newSha prompt',
      );
    });

    test(
      'a pre-column line whose whole command is the bare word "manifest" '
      'is not mistaken for the provenance marker',
      () {
        // Pre-column lines are one whitespace field with no internal tab, so
        // the shim's tab-boundary check must leave this one whole rather than
        // reading it as an armed marker with nothing after it. The falsifier
        // for the `--` guard: a naive prefix match on the word alone would
        // strip this to nothing and the command would silently vanish.
        declareAction(newSha, 'prompt');
        final bin = Directory(p.join(tmp.path, 'bin'));
        final exe = File(p.join(bin.path, 'manifest'))
          ..writeAsStringSync('''#!/usr/bin/env bash
echo ran >> "${p.join(tmp.path, 'manifest.log')}"
exit 0
''');
        Process.runSync('chmod', ['755', exe.path]);
        arm('attempted', armed('r1', '*', 'prompt', 'manifest'));

        expect(fireWith('prepared', ['$oldSha $newSha refs/heads/s1']).exitCode, 0);
        expect(
          File(p.join(tmp.path, 'manifest.log')).existsSync(),
          isTrue,
          reason: 'the bare word "manifest" is a command, not a stripped marker',
        );
      },
    );
  });

  test('the shim finds the entity from its own path, never by asking git', () {
    // The proof: with the fake git answering nothing at all, the tables are
    // still found and the listener still runs. Asking git would resolve to a
    // worktree's private directory, where no table lives — and would fail
    // SILENTLY, which is the whole reason self-location is a law.
    declareAction(newSha, 'prompt');
    arm('attempted', armed('r', '*', '*', listener('v')));
    expect(fireWith('prepared', ['$oldSha $newSha refs/heads/s1']).exitCode, 0);
    expect(logOf('v').readAsStringSync(), startsWith(repo));
  });

  group('a once line is spent by firing', () {
    test('it runs, and it is gone from the table', () async {
      declareAction(newSha, 'reply');
      arm('landed', armed('r9', '*', 'reply', listener('sub'), life: 'once'));

      expect(fireWith('committed', ['$oldSha $newSha refs/heads/s1']).exitCode, 0);
      expect(await appears(logOf('sub')), isTrue, reason: 'it fired');
      expect(tableOf('landed').trim(), isEmpty, reason: 'and it is spent');
    });

    test('a second occurrence finds nothing armed', () async {
      declareAction(newSha, 'reply');
      arm('landed', armed('r9', '*', 'reply', listener('sub'), life: 'once'));

      fireWith('committed', ['$oldSha $newSha refs/heads/s1']);
      expect(await appears(logOf('sub')), isTrue);
      logOf('sub').deleteSync();

      fireWith('committed', ['$oldSha $newSha refs/heads/s1']);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(logOf('sub').existsSync(), isFalse);
    });

    test('only the line that fired is spent', () {
      declareAction(newSha, 'prompt');
      File(p.join(repo, 'bentos', 'attempted')).writeAsStringSync([
        armed('r1', '*', 'prompt', listener('spent'), life: 'once'),
        armed('r2', '*', 'prompt', listener('standing')),
        armed('r3', '*', 'reply', listener('elsewhere'), life: 'once'),
      ].join('\n'));

      expect(fireWith('prepared', ['$oldSha $newSha refs/heads/s1']).exitCode, 0);
      final left = [
        for (final line in tableOf('attempted').split('\n'))
          if (line.trim().isNotEmpty) line.split('\t').first,
      ];
      expect(left, isNot(contains('r1')), reason: 'r1 fired');
      expect(left, contains('r2'), reason: 'r2 is not a once line');
      expect(
        left,
        contains('r3'),
        reason: 'r3 never matched, so it was never spent',
      );
    });

    test('refused at attempted, it is spent all the same', () {
      // The pruning happens at the moment of firing and before the command
      // runs: a refusal leaves the shim by `exit 1`, and a line pruned after
      // would fire forever.
      declareAction(newSha, 'prompt');
      arm('attempted',
          armed('r1', '*', 'prompt', listener('gate', exitCode: 1), life: 'once'));

      expect(fireWith('prepared', ['$oldSha $newSha refs/heads/s1']).exitCode, isNot(0));
      expect(tableOf('attempted').trim(), isEmpty);
    });

    test('a line armed before the lifetime column keeps its whole command', () {
      // Tables outlive the binary that wrote them. Read the old shape by the
      // new rule and the command loses its first argument — silently, in the
      // one place nothing is watching.
      declareAction(newSha, 'prompt');
      arm('attempted', ['r1', '*', 'prompt', '${listener('v')} --at /tmp/ent']
          .join('\t'));

      expect(fireWith('prepared', ['$oldSha $newSha refs/heads/s1']).exitCode, 0);
      expect(
        logOf('v').readAsStringSync().trim(),
        '--at /tmp/ent $repo refs/heads/s1 $oldSha $newSha prompt',
      );
      expect(tableOf('attempted'), contains('r1'), reason: 'and it lives on');
    });

    /// A listener that records **one argument per line**, which is the only way
    /// a test can see boundaries at all: `echo "$@"` prints the same text for
    /// one argument holding a space and for two arguments.
    String argvListener(String label) {
      final script = File(p.join(tmp.path, label))
        ..writeAsStringSync('''#!/usr/bin/env bash
for a in "\$@"; do echo "\$a"; done >> "${p.join(tmp.path, '$label.log')}"
exit 0
''');
      Process.runSync('chmod', ['755', script.path]);
      return script.path;
    }

    test('an argument holding a space arrives as one argument', () {
      // The table is what the caller's argv has to survive. Joined on a space
      // and split back by the shell, `sh -c 'echo hi'` reaches exec as three
      // words and does nothing the caller asked for — the silent failure the
      // command block exists to end.
      declareAction(newSha, 'prompt');
      arm(
        'attempted',
        ['r1', '*', 'prompt', 'always', '--', argvListener('argv'), 'two words']
            .join('\t'),
      );

      expect(fireWith('prepared', ['$oldSha $newSha refs/heads/s1']).exitCode, 0);
      expect(
        logOf('argv').readAsLinesSync().first,
        'two words',
        reason: 'the space is inside the argument, not between two',
      );
    });

    test('the command block carries every argument, in order', () {
      declareAction(newSha, 'prompt');
      arm(
        'attempted',
        [
          'r1',
          '*',
          'prompt',
          'always',
          '--',
          argvListener('argv'),
          '-c',
          'echo one two',
          'tail',
        ].join('\t'),
      );

      expect(fireWith('prepared', ['$oldSha $newSha refs/heads/s1']).exitCode, 0);
      expect(
        logOf('argv').readAsLinesSync(),
        ['-c', 'echo one two', 'tail', repo, 'refs/heads/s1', oldSha, newSha,
            'prompt'],
      );
    });

    test('a line armed before the command block still splits on whitespace', () {
      // The compatibility that makes the change safe to ship: an installation
      // armed by an older binary keeps firing exactly as it always did.
      declareAction(newSha, 'prompt');
      arm(
        'attempted',
        ['r1', '*', 'prompt', 'always', '${argvListener('argv')} -c tail']
            .join('\t'),
      );

      expect(fireWith('prepared', ['$oldSha $newSha refs/heads/s1']).exitCode, 0);
      expect(logOf('argv').readAsLinesSync().take(2).toList(), ['-c', 'tail']);
    });
  });
}
