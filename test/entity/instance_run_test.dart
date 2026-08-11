import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:bentos_userland/src/git/process_git.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// `Instance.run` — the API surface `entity run` now delegates to, proven
/// **called directly**, with no CLI layer between the assertion and the
/// primitive. `cli_run_test.dart` proves the CLI wiring; this proves the
/// member exists and does the real thing on its own.
///
/// Real Git, real modes, real processes, for the same reason `cli_run_test`
/// insists on them: an executable is a mode bit, and a fake port would only
/// ever prove a file nobody could have run.
void main() {
  const git = ProcessGit();
  late Directory scratch;
  late Directory site;

  setUp(() {
    scratch = Directory(
      Directory.systemTemp.createTempSync('instance_run_').resolveSymbolicLinksSync(),
    );
    site = Directory(p.join(scratch.path, 'site'))..createSync(recursive: true);
    Directory(p.join(site.path, '.place')).createSync(recursive: true);
  });

  tearDown(() {
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  const witness = r'''#!/usr/bin/env bash
set -u
report="$1"; code="$2"; shift 2
{
  echo "place=${BENTOS_PLACE-<unset>}"
  echo "entity=${BENTOS_ENTITY-<unset>}"
  echo "instance=${BENTOS_INSTANCE-<unset>}"
  echo "coord=${BENTOS_COORD-<unset>}"
  echo "args=$*"
} > "$report"
exit "$code"
''';

  const manifest = '''
name: probe.thing
type: probe.thing
cardinality: plural
functions:
  say.hello:
    exec: bin/witness
    deposits: greeting
  no.body:
    deposits: nothing
''';

  /// A bare repository holding [files] on `genesis`, with [executable] paths
  /// at mode 755. Installable as a source: a local path is a URL Git accepts.
  /// The same shape `cli_run_test.dart` builds its fixtures from, through the
  /// real port and not a fake one — an executable is a mode bit.
  String sourceRepository(
    String dirName, {
    required Map<String, String> files,
    Set<String> executable = const {},
  }) {
    final repository = p.join(scratch.path, dirName);
    git.init(repository);
    final work = Directory(p.join(scratch.path, 'work-$dirName'))
      ..createSync(recursive: true);
    for (final entry in files.entries) {
      File(p.join(work.path, entry.key))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(entry.value);
    }
    for (final path in executable) {
      Process.runSync('chmod', ['755', p.join(work.path, path)]);
    }
    final tree = git.writeTree(repository, workTree: work.path);
    final sha = git.commitTree(repository, tree: tree, parents: const [], message: 'authored\n');
    git.updateRef(
      repository,
      ref: Entity.genesisRef,
      newCommit: Commit(sha),
      expected: null,
    );
    work.deleteSync(recursive: true);
    return repository;
  }

  String report() => p.join(scratch.path, 'report');

  Map<String, String> reported(String path) {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: 'the witness never ran');
    return {
      for (final line in file.readAsLinesSync())
        line.substring(0, line.indexOf('=')): line.substring(line.indexOf('=') + 1),
    };
  }

  test('runs the declared function with the context laid, unedited exit code',
      () async {
    final source = sourceRepository(
      'probe.git',
      files: {'entity.yaml': manifest, 'bin/witness': witness},
      executable: {'bin/witness'},
    );
    final entity = await Entity.install(source, at: site.path);
    final instance = entity.instance('alpha')..create();

    final result = await instance.run(
      'say.hello',
      args: [report(), '0', 'extra', 'args'],
    );

    expect(result.exitCode, 0);
    final said = reported(report());
    expect(said['entity'], 'probe.thing');
    expect(said['instance'], 'alpha');
    expect(said['coord'], 'probe.thing:alpha');
    expect(said['place'], site.path);
    expect(said['args'], 'extra args');
  });

  test('the exit code is the body\'s, unedited', () async {
    final source = sourceRepository(
      'probe2.git',
      files: {'entity.yaml': manifest, 'bin/witness': witness},
      executable: {'bin/witness'},
    );
    final entity = await Entity.install(source, at: site.path);
    final instance = entity.instance('alpha')..create();

    final result = await instance.run('say.hello', args: [report(), '7']);

    expect(result.exitCode, 7);
  });

  test('a function the manifest does not declare throws FunctionNotDeclared',
      () async {
    final source = sourceRepository(
      'probe3.git',
      files: {'entity.yaml': manifest, 'bin/witness': witness},
      executable: {'bin/witness'},
    );
    final entity = await Entity.install(source, at: site.path);
    final instance = entity.instance('alpha')..create();

    expect(
      instance.run('never.declared'),
      throwsA(isA<FunctionNotDeclared>()),
    );
  });

  test('a function declared with no executable throws FunctionNotExecutable',
      () async {
    final source = sourceRepository(
      'probe4.git',
      files: {'entity.yaml': manifest, 'bin/witness': witness},
      executable: {'bin/witness'},
    );
    final entity = await Entity.install(source, at: site.path);
    final instance = entity.instance('alpha')..create();

    expect(
      instance.run('no.body'),
      throwsA(isA<FunctionNotExecutable>()),
    );
  });
}
