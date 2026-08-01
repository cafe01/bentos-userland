import 'dart:io';

import 'package:bentos_userland/src/entity/entity.dart';
import 'package:bentos_userland/src/git/process_git.dart';
import 'package:bentos_userland/src/place/place.dart';
import 'package:bentos_userland/src/place/place_runner.dart';
import 'package:test/test.dart';

/// `place materialize` — the constellation brought down, driven through the
/// coreutil against **real repositories**.
///
/// Real by necessity twice over: the verb's whole body is a worktree checkout,
/// which no fake filesystem performs, and the question it answers — *which
/// commit does this place's declaration mean* — is only interesting where a pin
/// and a genesis actually differ.
void main() {
  const git = ProcessGit();

  late Directory scratch;
  late String campus;

  Future<({String out, String err, int code})> runPlace(
    List<String> args, {
    required String cwd,
  }) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final runner = PlaceRunner(out: out, err: err, currentDirectory: cwd);
    await runner.run(args);
    return (out: out.toString(), err: err.toString(), code: runner.exitCode);
  }

  String gitDirOfInstallation(String place, String name) =>
      '${Place(place).plot(Entity.plotNamespace).path}/$name/${Entity.repositoryDirName}';

  /// A commit carrying exactly [files], on top of [parents].
  String commitWith(
    String gitDir,
    Map<String, String> files, {
    List<String> parents = const [],
  }) {
    final work = Directory.systemTemp.createTempSync('fixture_tree_');
    try {
      files.forEach((name, content) {
        File('${work.path}/$name').writeAsStringSync(content);
      });
      return git.commitTree(
        gitDir,
        tree: git.writeTree(gitDir, workTree: work.path),
        parents: parents,
        message: 'fixture',
      );
    } finally {
      work.deleteSync(recursive: true);
    }
  }

  /// An entity authored in [place], its genesis carrying [manifest] (none when
  /// null), with a further commit of state that the place is then pinned at.
  /// Returns both commits, because the whole question is which one comes down.
  ({String genesis, String state}) author(
    String place,
    String name, {
    String? manifest,
  }) {
    Entity(name, from: place).create();
    final gitDir = gitDirOfInstallation(place, name);

    final genesis = manifest == null
        ? git.revParse(gitDir, Entity.genesisRef)!.sha
        : commitWith(gitDir, {'manifest.yaml': manifest});
    if (manifest != null) {
      Process.runSync('git', ['--git-dir=$gitDir', 'update-ref', Entity.genesisRef, genesis]);
    }

    final state = commitWith(gitDir, {'state.txt': 'the state'}, parents: [genesis]);
    Place(place).pin(name, state);
    return (genesis: genesis, state: state);
  }

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('place_materialize_');
    campus = '${scratch.path}/campus';
    Directory('$campus/.place').createSync(recursive: true);
    Process.runSync('git', ['init', '--quiet', '--initial-branch=main', campus]);
  });

  tearDown(() {
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  group('what comes down is decided by cardinality', () {
    test('a singular entity comes down at the pin — its pin is its state', () async {
      final shas = author(campus, 'bentos.brain', manifest: 'cardinality: singular\n');

      final r = await runPlace(['materialize'], cwd: campus);
      expect(r.code, 0, reason: r.err);
      expect(r.out.trim(), 'bentos.brain\t$campus/bentos.brain\t${shas.state}');
      expect(File('$campus/bentos.brain/state.txt').readAsStringSync(), 'the state');
    });

    test('a plural entity comes down at genesis, whatever the pin says', () async {
      final shas = author(campus, 'bentos.chat', manifest: 'cardinality: plural\n');

      final r = await runPlace(['materialize'], cwd: campus);
      expect(r.code, 0, reason: r.err);
      expect(r.out.trim(), 'bentos.chat\t$campus/bentos.chat\t${shas.genesis}');
      expect(File('$campus/bentos.chat/manifest.yaml').existsSync(), isTrue);
      expect(
        File('$campus/bentos.chat/state.txt').existsSync(),
        isFalse,
        reason: 'no single sha means all the objects — taking the pin at face '
            'value would present one instance as the class',
      );
    });

    test('an undeclared cardinality reads as plural — genesis, conservatively', () async {
      final shas = author(campus, 'bentos.thing', manifest: 'type: thing\n');

      final r = await runPlace(['materialize'], cwd: campus);
      expect(r.code, 0, reason: r.err);
      expect(r.out.trim(), endsWith('\t${shas.genesis}'));
    });

    test('a freshly authored entity has no manifest at all, and still comes down', () async {
      final shas = author(campus, 'bentos.fresh');

      final r = await runPlace(['materialize'], cwd: campus);
      expect(r.code, 0, reason: r.err);
      expect(r.out.trim(), endsWith('\t${shas.genesis}'),
          reason: 'the ordinary condition of every new entity is the common '
              'path, so it must be the conservative one');
      expect(Directory('$campus/bentos.fresh').existsSync(), isTrue);
    });
  });

  group('re-materializing updates', () {
    test('the tree moves to the new declaration and the path stays one worktree', () async {
      author(campus, 'bentos.brain', manifest: 'cardinality: singular\n');
      await runPlace(['materialize'], cwd: campus);

      final gitDir = gitDirOfInstallation(campus, 'bentos.brain');
      final moved = commitWith(gitDir, {'state.txt': 'moved on'},
          parents: [git.revParse(gitDir, Entity.genesisRef)!.sha]);
      Place(campus).pin('bentos.brain', moved);

      final r = await runPlace(['materialize'], cwd: campus);
      expect(r.code, 0, reason: r.err);
      expect(r.out.trim(), endsWith('\t$moved'));
      expect(File('$campus/bentos.brain/state.txt').readAsStringSync(), 'moved on');

      final list = Process.runSync('git', ['--git-dir=$gitDir', 'worktree', 'list']);
      expect(
        RegExp(RegExp.escape('$campus/bentos.brain')).allMatches('${list.stdout}').length,
        1,
        reason: 'updated, never re-cloned and never doubly registered',
      );
    });
  });

  group('the descent', () {
    test('-r brings down the places nested under this one', () async {
      final workshop = '$campus/workshop';
      Directory('$workshop/.place').createSync(recursive: true);
      author(campus, 'bentos.brain', manifest: 'cardinality: singular\n');
      author(workshop, 'bentos.llm', manifest: 'cardinality: singular\n');

      final r = await runPlace(['materialize', '-r'], cwd: campus);
      expect(r.code, 0, reason: r.err);
      expect(File('$campus/bentos.brain/state.txt').existsSync(), isTrue);
      expect(File('$workshop/bentos.llm/state.txt').existsSync(), isTrue);
    });

    test('without -r the nested place is untouched', () async {
      final workshop = '$campus/workshop';
      Directory('$workshop/.place').createSync(recursive: true);
      author(campus, 'bentos.brain', manifest: 'cardinality: singular\n');
      author(workshop, 'bentos.llm', manifest: 'cardinality: singular\n');

      final r = await runPlace(['materialize'], cwd: campus);
      expect(r.code, 0, reason: r.err);
      expect(File('$campus/bentos.brain/state.txt').existsSync(), isTrue);
      expect(Directory('$workshop/bentos.llm').existsSync(), isFalse);
    });
  });

  group('a record the place cannot bring down', () {
    test('is reported and does not stop the constellation', () async {
      author(campus, 'bentos.brain', manifest: 'cardinality: singular\n');
      Place(campus).register('bentos.ghost', url: 'u', path: 'ghost', sha: '');

      final r = await runPlace(['materialize'], cwd: campus);
      expect(r.code, 1);
      expect(r.err, contains('bentos.ghost'));
      expect(File('$campus/bentos.brain/state.txt').existsSync(), isTrue,
          reason: 'brought down as far as it goes');
    });
  });
}
