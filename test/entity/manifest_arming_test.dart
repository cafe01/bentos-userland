import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:bentos_userland/src/git/process_git.dart';
import 'package:bentos_userland/src/place/place.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers.dart';

/// **Tier C — arming by manifest, on a repository this system never wrote.**
///
/// Every other fixture in the suite is born of [Entity.create], and a portal
/// that only ever meets its own hand cannot tell *the installer read the
/// manifest* from *the installer reproduced what it wrote itself*. This one
/// is hand-authored, bare, on `main`, with no `genesis` branch — the same
/// disjoint shape `helpers.dart::foreignRepository` uses, extended here with
/// the one thing that fixture never needed: a `functions:` table carrying
/// `exec:` and `on:`.
void main() {
  const git = ProcessGit();
  late Directory scratch;
  late Directory there;

  setUp(() {
    scratch = Directory(
      Directory.systemTemp.createTempSync('entity_manifest_arm_')
          .resolveSymbolicLinksSync(),
    );
    there = Directory(p.join(scratch.path, 'there'))..createSync(recursive: true);
    Directory(p.join(there.path, '.place')).createSync(recursive: true);
    File(p.join(there.path, '.place', 'place.yaml')).writeAsStringSync('name: there\n');
  });

  tearDown(() {
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  /// A bare repository this system never authored — no `genesis` branch, one
  /// ordinary commit on `main`, `entity.yaml` at its root written by hand.
  /// [manifest] is the whole document; the caller states it verbatim so the
  /// three scenarios below can each hand in exactly the shape they mean to
  /// exercise.
  String foreignEntity(String dirName, {required String manifest}) {
    final gitDir = p.join(scratch.path, dirName);
    git.init(gitDir, bare: true);
    final work = Directory.systemTemp.createTempSync('entity_manifest_arm_src-');
    try {
      File(p.join(work.path, 'entity.yaml')).writeAsStringSync(manifest);
      final good = File(p.join(work.path, 'bin', 'good'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('#!/usr/bin/env bash\nexit 0\n');
      Process.runSync('chmod', ['755', good.path]);
      final bad = File(p.join(work.path, 'bin', 'bad'))
        ..writeAsStringSync('#!/usr/bin/env bash\nexit 0\n');
      Process.runSync('chmod', ['755', bad.path]);
      final tree = git.writeTree(gitDir, workTree: work.path);
      final sha = git.commitTree(gitDir, tree: tree, parents: const [], message: 'initial\n', actor: testActor);
      git.updateRef(gitDir, ref: 'refs/heads/main', newCommit: Commit(sha), expected: null);
      git.updateRef(gitDir, ref: 'HEAD', newCommit: Commit(sha), expected: null);
    } finally {
      work.deleteSync(recursive: true);
    }
    return gitDir;
  }

  const manifest = '''
name: t.arm
type: bentos.mem
functions:
  good.fn:
    exec: bin/good
    on:
      - noun.landed
  bad.fn:
    exec: bin/bad
    on:
      - noun.whenever
  silent.fn:
    on:
      - other.attempted
''';

  test(
    'install writes a `*`/manifest line at the right phase, pointing at '
    '`entity run <name> <function>`; an unreadable `on:` row complains and '
    'the rest arms; a function with `on:` and no `exec:` complains too',
    () async {
      final source = foreignEntity('t.arm', manifest: manifest);
      final warnings = <String>[];

      final installed = await Entity.install(
        source,
        at: there.path,
        warn: warnings.add,
      );

      expect(installed.name, 't.arm');

      // good.fn: legible, has an executable — armed.
      final landed = installed.listeners
          .where((r) => r.pattern.phase == EventPhase.landed)
          .toList();
      expect(landed, hasLength(1));
      final line = landed.single;
      expect(line.instance, '*');
      expect(line.pattern.action, 'noun');
      expect(line.provenance, Provenance.manifest);
      expect(
        line.command,
        ['entity', '-C', Place(there.path).root.path, 'run', 't.arm', 'good.fn'],
      );

      // bad.fn: `on: noun.whenever` does not parse — complained about, and
      // nothing for it lands in any table.
      expect(
        warnings,
        contains(
          predicate<String>((w) => w.contains("'bad.fn'") && w.contains('noun.whenever')),
        ),
      );
      expect(
        installed.listeners.where((r) => r.command.contains('bad.fn')),
        isEmpty,
        reason: 'an illegible reaction is a complaint, never a line',
      );

      // silent.fn: `on:` with no `exec:` — declared and unrunnable, warned
      // about, and armed nowhere.
      expect(
        warnings,
        contains(
          predicate<String>(
            (w) => w.contains("'silent.fn'") && w.contains('no executable'),
          ),
        ),
      );
      expect(installed.listeners.where((r) => r.command.contains('silent.fn')), isEmpty);

      // And install itself never refused over any of it — one misspelled or
      // half-declared reaction is not a reason to reject a platform's
      // ordinary act.
      expect(installed.listeners, hasLength(1), reason: 'only good.fn armed');
    },
  );
}
