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
      ..writeAsStringSync(referenceTransactionShim);
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
      arm('attempted', ['r1', '*', 'prompt', listener('validator', exitCode: 1)].join('\t'));

      final result = fireWith('prepared', ['$oldSha $newSha refs/heads/s1']);
      expect(result.exitCode, isNot(0), reason: 'a non-zero exit aborts the update');
      expect(result.stderr.toString(), contains('refused by r1'));
    });

    test('a listener that consents lets it through, and runs in line', () {
      declareAction(newSha, 'prompt');
      arm('attempted', ['r1', '*', 'prompt', listener('validator')].join('\t'));

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
      arm('landed', ['r2', '*', 'reply', listener('subscriber')].join('\t'));

      expect(fireWith('committed', ['$oldSha $newSha refs/heads/s1']).exitCode, 0);
      expect(
        await appears(logOf('subscriber')),
        isTrue,
        reason: 'the landing is never held hostage to what it wakes',
      );
    });

    test('a subscriber that fails does not fail the landing', () async {
      declareAction(newSha, 'reply');
      arm('landed', ['r2', '*', 'reply', listener('bad', exitCode: 9)].join('\t'));
      expect(fireWith('committed', ['$oldSha $newSha refs/heads/s1']).exitCode, 0);
    });
  });

  test('the aborted phase publishes the refusal', () async {
    declareAction(newSha, 'prompt');
    arm('refused', ['r3', '*', '*', listener('onrefused')].join('\t'));
    expect(fireWith('aborted', ['$oldSha $newSha refs/heads/s1']).exitCode, 0);
    expect(await appears(logOf('onrefused')), isTrue);
  });

  group('what is not an action', () {
    setUp(() {
      declareAction(newSha, 'prompt');
      arm('landed', ['r', '*', '*', listener('any')].join('\t'));
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
      arm('attempted', ['r', '*', 'reply', listener('v', exitCode: 1)].join('\t'));
      expect(
        fireWith('prepared', ['$oldSha $newSha refs/heads/s1']).exitCode,
        0,
        reason: 'a listener armed on another noun never sees this act',
      );
    });

    test('an instance glob that does not match stays silent', () {
      declareAction(newSha, 'prompt');
      arm('attempted', ['r', 's2', 'prompt', listener('v', exitCode: 1)].join('\t'));
      expect(fireWith('prepared', ['$oldSha $newSha refs/heads/s1']).exitCode, 0);
    });

    test('a prefix glob selects a family of nouns', () {
      declareAction(newSha, 'tool-result');
      arm('attempted', ['r', '*', 'tool-*', listener('v', exitCode: 1)].join('\t'));
      expect(fireWith('prepared', ['$oldSha $newSha refs/heads/s1']).exitCode, isNot(0));
    });

    test('a commented line is not a fault', () {
      declareAction(newSha, 'prompt');
      File(p.join(repo, 'bentos', 'attempted')).writeAsStringSync(
        '# disabled for now\n\n${['r', '*', 'prompt', listener('v')].join('\t')}\n',
      );
      expect(fireWith('prepared', ['$oldSha $newSha refs/heads/s1']).exitCode, 0);
      expect(logOf('v').existsSync(), isTrue);
    });
  });

  test('the shim finds the entity from its own path, never by asking git', () {
    // The proof: with the fake git answering nothing at all, the tables are
    // still found and the listener still runs. Asking git would resolve to a
    // worktree's private directory, where no table lives — and would fail
    // SILENTLY, which is the whole reason self-location is a law.
    declareAction(newSha, 'prompt');
    arm('attempted', ['r', '*', '*', listener('v')].join('\t'));
    expect(fireWith('prepared', ['$oldSha $newSha refs/heads/s1']).exitCode, 0);
    expect(logOf('v').readAsStringSync(), startsWith(repo));
  });
}
