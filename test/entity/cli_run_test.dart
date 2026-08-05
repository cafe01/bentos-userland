import 'dart:io';

import 'package:bentos_userland/entity.dart';
// The concrete port is not part of the public surface — a caller never names
// it, because the ambient already is it. The tiers that must meet the machine
// are the one reader that does.
import 'package:bentos_userland/src/git/process_git.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'cli_harness.dart';
import 'helpers.dart';

/// `entity run` — against **the real substrate**, and it has to be.
///
/// The claim is that a declared executable runs, and an executable is a mode
/// bit: the fake port writes worktrees as ordinary files, so a green there
/// would be a green about a file nobody could have executed. Real Git, real
/// modes, real processes — the same tier the shim is proven at.
///
/// The witness is **written by hand** and reports what it received. Nothing
/// about the context is asserted against a value the code under judgment
/// minted: the body says what reached it, and the gate reads that.
void main() {
  const git = ProcessGit();
  late Directory scratch;
  late Directory site;

  setUp(() {
    scratch = Directory(
      Directory.systemTemp.createTempSync('entity_run_').resolveSymbolicLinksSync(),
    );
    site = Directory(p.join(scratch.path, 'site'))..createSync(recursive: true);
    Directory(p.join(site.path, '.place')).createSync(recursive: true);
    File(p.join(site.path, '.place', 'place.yaml'))
        .writeAsStringSync('name: site\n');
  });

  tearDown(() {
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  Future<Run> cli(List<String> args, {String? cwd}) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final runner = EntityRunner(
      out: out,
      err: err,
      currentDirectory: cwd ?? site.path,
    );
    await runWithGitAsync(git, () => runner.run(args));
    return (out: out.toString(), err: err.toString(), code: runner.exitCode);
  }

  /// The witness: a program written here, in full, that reports the context it
  /// was given and exits with the number it was told to. It is the whole reason
  /// this gate can say anything about what `run` laid — a fixture minted by the
  /// entity machinery could only ever agree with itself.
  const witness = r'''#!/usr/bin/env bash
set -u
report="$1"; code="$2"; shift 2
{
  echo "place=${BENTOS_PLACE-<unset>}"
  echo "entity=${BENTOS_ENTITY-<unset>}"
  echo "instance=${BENTOS_INSTANCE-<unset>}"
  echo "coord=${BENTOS_COORD-<unset>}"
  echo "cwd=$PWD"
  echo "args=$*"
} > "$report"
exit "$code"
''';

  /// A manifest authored by hand, in the vocabulary a real entity uses:
  /// `deposits` and `on:` ride along precisely so that a gate can watch `run`
  /// ignore them.
  const manifest = '''
name: probe.thing
type: probe.thing
cardinality: plural
functions:
  say.hello:
    exec: bin/witness
    deposits: greeting
    on:
      - greeting.landed
  no.body:
    deposits: nothing
''';

  /// A bare repository holding [files] on `genesis`, with [executable] paths at
  /// mode 755. Installable as a source: a local path is a URL Git accepts.
  String sourceRepository(
    String dirName, {
    required Map<String, String> files,
    Set<String> executable = const {},
    String? onto,
    String? gitDir,
  }) {
    final repository = gitDir ?? p.join(scratch.path, dirName);
    if (gitDir == null) git.init(repository);
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
    final sha = git.commitTree(
      repository,
      tree: tree,
      parents: [?onto],
      message: 'authored\n',
    );
    git.updateRef(
      repository,
      ref: Entity.genesisRef,
      newCommit: Commit(sha),
      expected: onto == null ? null : Commit(onto),
    );
    work.deleteSync(recursive: true);
    return repository;
  }

  /// The ordinary installed entity every test below starts from — **with one
  /// instance born**.
  ///
  /// The birth is not scenery. Every test here names a coordinate, and if none
  /// of them named a live instance, *`run` never looks the instance up* would
  /// be a law no single test could fall for on its own: resolving the instance
  /// would redden the whole file, and a claim that everything catches is a
  /// claim nothing pins. Born here, unborn in exactly one test below.
  Future<void> install() async {
    final source = sourceRepository(
      'probe.git',
      files: {'entity.yaml': manifest, 'bin/witness': witness},
      executable: {'bin/witness'},
    );
    final installed = await cli(['install', source]);
    expect(installed.code, 0, reason: installed.err);
    final born = await cli(['new', 'probe.thing', 'alpha']);
    expect(born.code, 0, reason: born.err);
  }

  /// What the witness reported, as a map.
  Map<String, String> reported(String path) {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: 'the witness never ran');
    return {
      for (final line in file.readAsLinesSync())
        line.substring(0, line.indexOf('=')):
            line.substring(line.indexOf('=') + 1),
    };
  }

  String report() => p.join(scratch.path, 'report');

  // ---------------------------------------------------------------- the verb

  test('resolves the name to the executable and lays the context', () async {
    await install();

    final ran = await cli([
      'run',
      'probe.thing:alpha',
      'say.hello',
      report(),
      '0',
      'extra',
      '--flag-of-the-body',
    ]);

    expect(ran.code, 0, reason: ran.err);
    final said = reported(report());
    expect(said['entity'], 'probe.thing');
    expect(said['instance'], 'alpha');
    expect(said['coord'], 'probe.thing:alpha');
    expect(said['place'], site.path);
    // Falsified by dropping any one export: each of the four is the only line
    // that falls, and the other three stay green.
    expect(said['args'], 'extra --flag-of-the-body');
    // The body's own flags reach the body. Falsified by letting the parser read
    // trailing options: this fails with a usage error before anything runs, and
    // nothing else in the file moves.
  });

  test('the instance travels verbatim — never looked up, never born', () async {
    await install();

    // No instance of this name exists, and `run` is forbidden to care: it does
    // not read the ref, so it cannot refuse on it.
    final ran = await cli(
      ['run', 'probe.thing:never-born', 'say.hello', report(), '0'],
    );

    expect(ran.code, 0, reason: ran.err);
    expect(reported(report())['instance'], 'never-born');
    // Falsified by resolving the instance before running: this test alone goes
    // red, which is what makes *run interprets nothing* a pinned claim rather
    // than an intention in a doc comment.
  });

  test("the exit code is the body's, unedited", () async {
    await install();

    final ran = await cli(['run', 'probe.thing:alpha', 'say.hello', report(), '7']);

    expect(ran.code, 7);
    expect(reported(report())['entity'], 'probe.thing');
    // Falsified by reporting 0 on a body that failed, or by mapping failure to
    // one of the coreutil's own numbers: only this expectation falls.
  });

  test('the bytes executed are the stage’s own', () async {
    await install();
    final staged = p.join(
      site.path,
      '.place',
      Entity.plotNamespace,
      'probe.thing',
      Entity.classDirName,
    );

    // Rewritten in the stage and nowhere else: the commit does not move, so the
    // installation still holds what it held. If `run` read the tree out of Git
    // at call time, the original body would answer here.
    File(p.join(staged, 'bin', 'witness')).writeAsStringSync(
      '#!/usr/bin/env bash\necho rewritten > "\$1"\n',
    );

    final ran = await cli(['run', 'probe.thing:alpha', 'say.hello', report(), '0']);

    expect(ran.code, 0, reason: ran.err);
    expect(File(report()).readAsStringSync().trim(), 'rewritten');
  });

  // ------------------------------------------------------------ the refusals

  test('a function the manifest does not declare refuses, and runs nothing',
      () async {
    await install();

    final ran = await cli(['run', 'probe.thing:alpha', 'say.goodbye', report(), '0']);

    expect(ran.code, 1);
    expect(ran.err, contains("declares no function 'say.goodbye'"));
    expect(File(report()).existsSync(), isFalse);
  });

  test('a function declared with no executable refuses in its own words',
      () async {
    await install();

    final ran = await cli(['run', 'probe.thing:alpha', 'no.body', report(), '0']);

    expect(ran.code, 1);
    // Declared-and-unrunnable is not the same absence as never-declared, and
    // the two messages are disjoint. Falsified by collapsing the manifest's
    // function table to the rows that carry an exec: this test falls and the
    // one above it stays green, which is what proves they are two claims.
    expect(ran.err, contains("declares 'no.body' with no executable"));
    expect(ran.err, isNot(contains('declares no function')));
  });

  String stagePath([String? at]) => p.join(
        at ?? site.path,
        '.place',
        Entity.plotNamespace,
        'probe.thing',
        Entity.classDirName,
      );

  /// The remedy exactly as the refusal printed it, split into an argv — **the
  /// witness of a different matter than the assertions above**. Everything else
  /// here reads a value the code computed; this reads the sentence a human is
  /// handed, and hands it back untouched.
  ///
  /// The program's own name is asserted and then dropped, because the runner
  /// under test *is* `entity`: what would otherwise go untested is that the line
  /// names the program a reader has, rather than a verb spelled for this file.
  List<String> cureIn(String err) {
    final line = err
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.contains('entity -C '));
    final argv = line.substring(line.indexOf('entity -C ')).split(' ');
    expect(argv.first, 'entity', reason: 'the cure must name a real program');
    return argv.skip(1).toList();
  }

  test('an absent class tree refuses, and the cure it prints stands it up',
      () async {
    await install();
    Directory(stagePath()).deleteSync(recursive: true);

    final ran = await cli(['run', 'probe.thing:alpha', 'say.hello', report(), '0']);

    expect(ran.code, 1);
    expect(ran.err, contains('no class tree'));
    expect(File(report()).existsSync(), isFalse);

    // Typed verbatim, and from outside the place: a cure that carries no
    // vantage resolves against wherever the reader stands, which is another
    // installation of the same name or none at all.
    final cured = await cli(cureIn(ran.err), cwd: scratch.path);
    expect(cured.code, 0, reason: cured.err);

    final again = await cli(['run', 'probe.thing:alpha', 'say.hello', report(), '0']);
    expect(again.code, 0, reason: again.err);
    expect(reported(report())['entity'], 'probe.thing');
  });

  test("another entity's worktree is not this entity's stage", () async {
    await install();
    final made = await cli(['create', 'other.thing']);
    expect(made.code, 0, reason: made.err);

    // A **registered** worktree, and of the wrong repository — the state the
    // register alone cannot catch, since it answers *somebody holds this* and
    // the question is *do we*. Standing here by hand, from the other entity's
    // own repository, at the other entity's own genesis.
    await runWithGitAsync(git, () async {
      final ours = Entity('probe.thing', from: site.path);
      final theirs = Entity('other.thing', from: site.path);
      ours.stagedClass.release();
      git.worktreeAdd(
        repositoryOf(site.path, 'other.thing'),
        path: stagePath(),
        at: theirs.genesis,
      );
    });
    final foreign = git.worktreeHead(stagePath())!;

    final ran = await cli(['run', 'probe.thing:alpha', 'say.hello', report(), '0']);

    expect(ran.code, 1);
    expect(ran.err, isNot(contains(foreign.short)),
        reason: "a sha from another entity's line is not ours to report");
    expect(ran.err, contains('never registered'));
    expect(File(report()).existsSync(), isFalse);
  });

  test('a directory that is not ours blocks the stage, and is never discarded',
      () async {
    await install();
    final staged = Directory(stagePath());
    staged.deleteSync(recursive: true);
    // Somebody else's files, standing where the class stands. The one state
    // that has no automatic cure: what is here is only knowable by whoever put
    // it here.
    staged.createSync(recursive: true);
    File(p.join(staged.path, 'theirs.txt')).writeAsStringSync('not ours\n');

    final ran = await cli(['run', 'probe.thing:alpha', 'say.hello', report(), '0']);

    expect(ran.code, 1);
    expect(ran.err, contains('never registered'));
    expect(ran.err, contains('move what stands there aside'));

    // And the cure refuses rather than clearing the way for itself.
    final refused = await cli(cureIn(ran.err), cwd: scratch.path);
    expect(refused.code, EntityRunner.refusedCode, reason: refused.err);
    expect(refused.err, contains('not a worktree of ours'));
    expect(
      File(p.join(staged.path, 'theirs.txt')).readAsStringSync(),
      'not ours\n',
      reason: 'a verb that clears what it does not own deletes strangers',
    );
  });

  test('a stale class tree refuses, and the cure it prints is a cure', () async {
    await install();
    final repository = repositoryOf(site.path, 'probe.thing');
    final held = git.revParse(repository, Entity.genesisRef)!;

    // The class moves: a second authoring landed on genesis, in the
    // installation's own repository, with a body that answers differently.
    sourceRepository(
      'probe.git',
      gitDir: repository,
      onto: held.sha,
      files: {
        'entity.yaml': manifest,
        'bin/witness': '#!/usr/bin/env bash\necho second > "\$1"\n',
      },
      executable: {'bin/witness'},
    );

    final refused = await cli(
      ['run', 'probe.thing:alpha', 'say.hello', report(), '0'],
    );
    expect(refused.code, 1);
    expect(refused.err, contains('this place does not declare'));
    expect(File(report()).existsSync(), isFalse,
        reason: 'a stale tree must not run — that is the whole law');

    // The remedy is taken from the refusal itself and typed back verbatim. A
    // refusal that names a verb which does not move this tree would be a dead
    // end, and a dead end is a worse law than silence.
    //
    // **Typed from somewhere else on purpose.** A cure retyped inside the place
    // it was printed in resolves by accident: the vantage the reader happens to
    // stand in agrees with the one the refusal meant. Run from outside, a cure
    // that omits the vantage finds another installation of the same name — or
    // none — and answers zero having moved nothing. That is not hypothetical:
    // it is what the first line this verb printed did when it was tried by hand.
    final cure = refused.err
        .split('\n')
        .firstWhere((line) => line.contains('bring it forward:'))
        .split('bring it forward:')
        .last
        .trim()
        .split(' ')
        .skip(1)
        .toList();
    final cured = await cli(cure, cwd: scratch.path);
    expect(cured.code, 0, reason: cured.err);

    final ran = await cli(['run', 'probe.thing:alpha', 'say.hello', report(), '0']);
    expect(ran.code, 0, reason: ran.err);
    expect(File(report()).readAsStringSync().trim(), 'second');
  });

  // ------------------------------------------------------------- the grammar

  test('a bare name is a usage failure — the coordinate is always required',
      () async {
    await install();

    final ran = await cli(['run', 'probe.thing', 'say.hello']);

    expect(ran.code, 64);
    expect(File(report()).existsSync(), isFalse);
  });

  test('a coordinate carrying a path is a usage failure', () async {
    await install();

    final ran = await cli(
      ['run', 'probe.thing:alpha:llm/channel.toml', 'say.hello', report(), '0'],
    );

    expect(ran.code, 64);
    expect(File(report()).existsSync(), isFalse);
  });

  // ------------------------------------------------------------ the staging

  test('installing stands the class up at the genesis it holds', () async {
    await install();

    await runWithGitAsync(git, () async {
      final entity = Entity('probe.thing', from: site.path);
      expect(entity.stagedClass.at, entity.genesis);
      expect(
        File(p.join(entity.stagedClass.directory.path, 'bin', 'witness'))
            .existsSync(),
        isTrue,
      );
    });
  });

  test('authoring stands one up too, so a first landing has a tree to move',
      () async {
    final made = await cli(['create', 'authored.thing']);
    expect(made.code, 0, reason: made.err);

    await runWithGitAsync(git, () async {
      final entity = Entity('authored.thing', from: site.path);
      // Empty, and standing at genesis all the same: an author who lands a
      // manifest can bring this forward, where an absence has no verb aimed at
      // it. Falsified by staging only on install — `create` then leaves a hole
      // the printed cure cannot fill.
      expect(entity.stagedClass.at, entity.genesis);
    });
  });

  // --------------------------------------------------------- the neighbourhood

  /// **A place with a repository above it**, which is the ordinary condition and
  /// not an exotic one: a habitat is a checkout, and every place inside it has a
  /// repository overhead that answers questions nobody asked it.
  ///
  /// Every other gate in this file is born under `systemTemp` with nothing
  /// above, and that is a population with one value on the axis the law speaks
  /// about — *which repository answers for this directory*. Under one value the
  /// wrong reading has nothing to be wrong with: it fails to resolve, and the
  /// honest branch runs for the dishonest reason.
  group('a place inside a repository', () {
    void enclose(String path) {
      Process.runSync('git', ['init', '--quiet', path]);
      Process.runSync('git', [
        '-C', path,
        '-c', 'user.email=gate@bentos',
        '-c', 'user.name=gate',
        'commit', '--quiet', '--allow-empty', '-m', 'the neighbour',
      ]);
    }

    /// The head the enclosing repository would answer with — the number that
    /// must never appear in anything this entity says about itself.
    String neighbourHead(String path) => Process.runSync(
          'git',
          ['-C', path, 'rev-parse', 'HEAD'],
        ).stdout.toString().trim();

    test('the stage reports its own repository, never the one above it',
        () async {
      enclose(scratch.path);
      await install();

      // The campus state, made by hand: the files stand, and the link that made
      // them a worktree is gone. Nothing of the machinery under judgment minted
      // this — which is the point, since the machinery cannot produce the state
      // it fails to describe.
      File(p.join(stagePath(), '.git')).deleteSync();

      final ran = await cli(['run', 'probe.thing:alpha', 'say.hello', report(), '0']);

      expect(ran.code, 1);
      expect(
        ran.err,
        isNot(contains(neighbourHead(scratch.path).substring(0, 7))),
        reason: 'the head above the place is not this entity to report',
      );
      expect(ran.err, contains('never registered'));
      expect(File(report()).existsSync(), isFalse);
    });

    test('the cure works with a repository overhead, exactly as without',
        () async {
      enclose(scratch.path);
      await install();
      Directory(stagePath()).deleteSync(recursive: true);

      final ran = await cli(['run', 'probe.thing:alpha', 'say.hello', report(), '0']);
      expect(ran.code, 1);

      final cured = await cli(cureIn(ran.err), cwd: scratch.path);
      expect(cured.code, 0, reason: cured.err);

      final again = await cli(['run', 'probe.thing:alpha', 'say.hello', report(), '0']);
      expect(again.code, 0, reason: again.err);
    });
  });
}
