import 'dart:convert';
import 'dart:io';

import 'package:bentos_userland/entity.dart';
// The pin is read straight off the place, exactly as the manifest-arming suite
// reads it: the guard's claim is about the gitlink and not about a report.
import 'package:bentos_userland/src/place/place.dart';
// The plot's layout is the arming component's alone and stays off the public
// surface, so the table's own laws are proven where they live — and the
// repository is reached through the package-private seam, never by a consumer.
import 'package:bentos_userland/src/entity/arming/arming.dart';
import 'package:bentos_userland/src/entity/arming/arming_provenance.dart';
import 'package:bentos_userland/src/entity/entity.dart' show gitDirOf;
// The order of operations is normative and unreachable from end state, so the
// substrate is watched through a port of our own — which is the port interface
// itself, and the real one where the claim is about Git rather than about us.
import 'package:bentos_userland/src/entity/dispatch.dart';
import 'package:bentos_userland/src/git/process_git.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../git/fake_git.dart' show NetworkRecordingGit;
import 'helpers.dart';

/// **The installation's life after its constructor** — `refit` and `upgrade`,
/// asserted against the design specification at
/// `domain/bentos/entity/installation/design-specification`.
///
/// Red until construction, and each assert fails naming the member it wants.
void main() {
  group('replaceProvenance — R2.4 and R4.1', () {
    late Site site;
    late Entity llm;
    late ArmingTables tables;

    setUp(() {
      site = Site();
      site.run(() {
        llm = Entity('bentos.llm', from: site.root.path).create();
        tables = ArmingTables(gitDirOf(llm), entity: llm.name);
      });
    });
    tearDown(() => site.dispose());

    Arming declaring(String pattern, {String command = 'run-it'}) => Arming(
          instance: '*',
          pattern: EventPattern.parse(pattern),
          command: ['entity', 'run', 'bentos.llm', command],
        );

    /// **The defect R4.1 names, characterized against today's code.**
    ///
    /// This is the behaviour `_armDeclared` has: it appends. Nothing has ever
    /// run it twice, which is the only reason the installer looks idempotent —
    /// and the day a verb re-reads the manifest, every declared reaction fires
    /// twice per act, silently. Green today on purpose: it is the *before*
    /// picture, and it goes red the day somebody makes `add` deduplicate,
    /// which would be a different design than the one specified.
    test('today: arming the same declared line twice appends twice', () {
      site.run(() {
        for (var i = 0; i < 2; i++) {
          tables.add(
            instance: '*',
            pattern: EventPattern.parse('prompt.landed'),
            command: ['entity', 'run', 'bentos.llm', 'run-it'],
            provenance: Provenance.manifest,
          );
        }
        final manifestLines = tables.all
            .where((r) => r.provenance == Provenance.manifest)
            .toList();
        expect(
          manifestLines.length,
          2,
          reason: 'the duplicate-append defect R4.1 names — two lines, one '
              'declaration. replaceProvenance is what closes it.',
        );
      });
    });

    test('R4.1: applying the same declaration twice leaves exactly one line', () {
      site.run(() {
        for (var i = 0; i < 2; i++) {
          tables.replaceProvenance(
            Provenance.manifest,
            declared: [declaring('prompt.landed')],
          );
        }
        final manifestLines = tables.all
            .where((r) => r.provenance == Provenance.manifest)
            .toList();
        expect(manifestLines.length, 1);
        expect(manifestLines.single.pattern.action, 'prompt');
      });
    });

    test('R2.4: every line of the provenance is replaced wholesale', () {
      site.run(() {
        tables.replaceProvenance(
          Provenance.manifest,
          declared: [declaring('prompt.landed'), declaring('tool.landed')],
        );
        tables.replaceProvenance(
          Provenance.manifest,
          declared: [declaring('turn.landed')],
        );
        final actions = tables.all
            .where((r) => r.provenance == Provenance.manifest)
            .map((r) => r.pattern.action)
            .toList();
        expect(
          actions,
          ['turn'],
          reason: 'the count after, never a delta: a reaction the manifest no '
              'longer declares must not survive the reading that dropped it.',
        );
      });
    });

    test('a hand-armed line is untouched, and its order is preserved', () {
      site.run(() {
        final first = llm.on(
          {EventPattern.parse('prompt.landed')},
          command: ['by-hand-one'],
        );
        final second = llm.on(
          {EventPattern.parse('tool.landed')},
          command: ['by-hand-two'],
        );
        tables.replaceProvenance(
          Provenance.manifest,
          declared: [declaring('prompt.landed')],
        );
        final byHand = tables.all
            .where((r) => r.provenance == Provenance.hand)
            .toList();
        expect(byHand.map((r) => r.id), [first.id, second.id]);
        expect(byHand.map((r) => r.command), [
          ['by-hand-one'],
          ['by-hand-two'],
        ]);
      });
    });

    test('the returned registrations are the newly minted ones, in order', () {
      site.run(() {
        final armed = tables.replaceProvenance(
          Provenance.manifest,
          declared: [
            declaring('prompt.landed', command: 'first'),
            declaring('tool.landed', command: 'second'),
          ],
        );
        expect(armed.map((r) => r.command.last), ['first', 'second']);
        expect(armed.map((r) => r.id).toSet().length, 2);
        expect(armed.every((r) => r.provenance == Provenance.manifest), isTrue);
      });
    });

    test('a refused command leaves every table exactly as it stood', () {
      site.run(() {
        llm.on({EventPattern.parse('prompt.landed')}, command: ['standing']);
        final before = {
          for (final phase in EventPhase.values)
            phase: tables.tableFor(phase).existsSync()
                ? tables.tableFor(phase).readAsBytesSync()
                : null,
        };
        expect(
          () => tables.replaceProvenance(
            Provenance.manifest,
            declared: [
              declaring('prompt.landed'),
              Arming(
                instance: '*',
                pattern: EventPattern.parse('tool.landed'),
                // A tab has no form on the wire, and the check runs before one
                // byte is rewritten.
                command: ['entity', 'run\twith-a-tab'],
              ),
            ],
          ),
          throwsA(isA<ArgumentError>()),
        );
        for (final phase in EventPhase.values) {
          final table = tables.tableFor(phase);
          expect(
            table.existsSync() ? table.readAsBytesSync() : null,
            before[phase],
            reason: 'checked before any table is rewritten, so a refusal is '
                'not a partial write with an exception on top',
          );
        }
      });
    });

    test('a phase with nothing of this provenance and nothing declared is '
        'neither created nor touched', () {
      site.run(() {
        expect(tables.tableFor(EventPhase.refused).existsSync(), isFalse);
        tables.replaceProvenance(
          Provenance.manifest,
          declared: [declaring('prompt.landed')],
        );
        expect(
          tables.tableFor(EventPhase.refused).existsSync(),
          isFalse,
          reason: 'a rewrite of nothing writes nothing — an empty table is a '
              'file that did not have to exist',
        );
      });
    });

    test('an empty declaration removes the provenance and keeps the rest', () {
      site.run(() {
        final byHand = llm.on(
          {EventPattern.parse('prompt.landed')},
          command: ['standing'],
        );
        tables.replaceProvenance(
          Provenance.manifest,
          declared: [declaring('tool.landed')],
        );
        final armed = tables.replaceProvenance(
          Provenance.manifest,
          declared: const [],
        );
        expect(armed, isEmpty);
        expect(tables.all.map((r) => r.id), [byHand.id]);
      });
    });

    test('the rewrite is atomic against a real reader process — never a torn '
        'set of lines', () async {
      const sizeA = 40, sizeB = 25;
      final setA = [
        for (var i = 0; i < sizeA; i++) declaring('prompt.landed', command: 'a$i'),
      ];
      final setB = [
        for (var i = 0; i < sizeB; i++) declaring('prompt.landed', command: 'b$i'),
      ];
      site.run(() => tables.replaceProvenance(Provenance.manifest, declared: setA));

      final reader = await Process.start(
        Platform.resolvedExecutable,
        [
          'run',
          'test/entity/tools/arming_table_reader.dart',
          gitDirOf(llm),
          '$sizeA',
          '$sizeB',
          '3000',
        ],
        workingDirectory: Directory.current.path,
      );
      final readerErr = StringBuffer();
      reader.stderr.transform(utf8.decoder).listen(readerErr.write);

      final deadline = DateTime.now().add(const Duration(seconds: 3));
      var flip = false;
      while (DateTime.now().isBefore(deadline)) {
        site.run(() => tables.replaceProvenance(
              Provenance.manifest,
              declared: flip ? setA : setB,
            ));
        flip = !flip;
      }

      final code = await reader.exitCode;
      expect(code, 0, reason: readerErr.toString());
    }, timeout: const Timeout(Duration(minutes: 1)));
  });

  group('refit — the apparatus half', () {
    late Site site;
    late Entity llm;
    late String gitDir;

    setUp(() {
      site = Site();
      site.run(() {
        llm = Entity('bentos.llm', from: site.root.path).create();
        gitDir = gitDirOf(llm);
      });
    });
    tearDown(() => site.dispose());

    File shimOf() => File(p.join(gitDir, ArmingTables.hookPath));
    String stagePath() => p.join(p.dirname(gitDir), Entity.classDirName);

    /// Every ref under `refs/heads/`, with what it stands at — the shape the
    /// guard quantifies over, read the same way in both verbs' groups.
    Map<String, String?> headsOf() => {
          for (final branch in site.git.branches(gitDir))
            branch: site.git.revParse(gitDir, 'refs/heads/$branch')?.sha,
        };

    Map<String, List<int>?> tableBytes() {
      final tables = ArmingTables(gitDir);
      return {
        for (final phase in EventPhase.values)
          phase.name: tables.tableFor(phase).existsSync()
              ? tables.tableFor(phase).readAsBytesSync()
              : null,
      };
    }

    test('the shim is rewritten, unconditionally, from the running coreutil', () {
      site.run(() {
        shimOf().writeAsStringSync('#!/bin/sh\n# a shim from an older vintage\n');
        final report = llm.refit();
        expect(report.shim, shimOf().path);
        expect(
          shimOf().readAsStringSync(),
          isNot(contains('an older vintage')),
          reason: 'the coreutil is the shim\'s only author, so its previous '
              'content and vintage are never consulted',
        );
        expect(shimOf().readAsStringSync(), contains(llm.name));
      });
    });

    test('a shim deleted outright comes back', () {
      site.run(() {
        shimOf().deleteSync();
        llm.refit();
        expect(shimOf().existsSync(), isTrue);
      });
    });

    test('it writes no ref', () {
      site.run(() {
        final before = headsOf();
        llm.refit();
        expect(
          headsOf(),
          before,
          reason: 'the apparatus is derived from the content, and content is '
              'what this verb does not touch',
        );
      });
    });

    test('it moves no place pin', () {
      site.run(() {
        final before = Place(site.root.path).lookup(llm.name)!.sha;
        llm.refit();
        expect(Place(site.root.path).lookup(llm.name)!.sha, before);
      });
    });

    test('it changes no line in any arming table', () {
      site.run(() {
        llm.on({EventPattern.parse('prompt.landed')}, command: ['standing']);
        final before = tableBytes();
        llm.refit();
        expect(tableBytes(), before);
      });
    });

    test('it requires no remote, and none is declared here', () {
      site.run(() {
        expect(llm.remotes, isEmpty);
        expect(llm.refit(), isA<RefitReport>());
      });
    });

    test('it reaches the network never — the strong witness, not the argued '
        'one', () {
      // A synchronous member cannot itself await a network verb, so the claim
      // has always held by shape. This is the resolution the shape argument
      // was standing in for: a Git that records every reach, standing behind
      // the verb, asserting the record stays empty.
      final recorder = NetworkRecordingGit();
      final watchedSite = Site('llm-recorder', recorder);
      addTearDown(watchedSite.dispose);
      watchedSite.run(() {
        final watchedLlm = Entity('bentos.llm', from: watchedSite.root.path)
            .create();
        watchedLlm.refit();
      });

      expect(recorder.networkCalls, isEmpty);
    });

    test('twice in succession leaves the installation byte-identical to once', () {
      site.run(() {
        llm.on({EventPattern.parse('prompt.landed')}, command: ['standing']);
        llm.refit();
        final shim = shimOf().readAsBytesSync();
        final tables = tableBytes();
        final heads = headsOf();
        final pin = Place(site.root.path).lookup(llm.name)!.sha;

        llm.refit();
        expect(shimOf().readAsBytesSync(), shim);
        expect(tableBytes(), tables);
        expect(headsOf(), heads);
        expect(Place(site.root.path).lookup(llm.name)!.sha, pin);
      });
    });

    test('it throws EntityNotInstalled where the walk answers nothing', () {
      site.run(() {
        expect(
          () => Entity('bentos.absent', from: site.root.path).refit(),
          throwsA(isA<EntityNotInstalled>()),
        );
      });
    });

  });

  group('refit — the apparatus half, against real Git', () {
    // Two claims [FakeGit] cannot honestly witness, both named in the fixture
    // audit: a deleted directory, and a stranger's worktree. Both ask what the
    // possession model is a register OR the disk — and a register-backed
    // fake either has to be told by hand what the disk holds, or answers a
    // question about its own bookkeeping rather than about Git. Real Git's
    // `worktree list` and `rev-parse` are the only honest witness here.
    const git = ProcessGit();
    late Directory root;
    late Entity llm;
    late String gitDir;

    setUp(() {
      root = Directory(Directory.systemTemp
          .createTempSync('entity_material_')
          .resolveSymbolicLinksSync());
      Directory(p.join(root.path, '.place')).createSync(recursive: true);
      File(p.join(root.path, '.place', 'place.yaml'))
          .writeAsStringSync('name: material\n');
      runWithGit(git, () {
        llm = Entity('bentos.llm', from: root.path).create();
        gitDir = gitDirOf(llm);
      });
    });
    tearDown(() => root.deleteSync(recursive: true));

    String stagePath() => p.join(p.dirname(gitDir), Entity.classDirName);

    test('the class tree is re-staged at the genesis already held', () {
      runWithGit(git, () {
        final held = git.revParse(gitDir, Entity.genesisRef);
        Directory(stagePath()).deleteSync(recursive: true);
        final report = llm.refit();
        expect(report.stagedAt, held);
        expect(Directory(stagePath()).existsSync(), isTrue);
      });
    });

    test('a stage directory this repository never registered is refused, '
        'never discarded', () {
      runWithGit(git, () {
        final stage = Directory(stagePath());
        if (stage.existsSync()) stage.deleteSync(recursive: true);

        // The hard case the note demands: not a bare directory with a stray
        // file, but a worktree **real Git itself made**, of a repository of
        // its own — a `.git` file that resolves to an actual gitdir, real
        // Git's own answer to "who does this belong to", and that answer is
        // "not this repository". A register-backed fake would have to be told
        // by hand that this is alien; real Git already knows, because its own
        // worktree register was never told about this path at all.
        final foreignGitDir = p.join(root.path, 'foreign.git');
        git.init(foreignGitDir, bare: true);
        final work = Directory.systemTemp.createTempSync('entity_foreign_wt-');
        File(p.join(work.path, 'not-ours.txt'))
            .writeAsStringSync('somebody else stood here');
        final tree = git.writeTree(foreignGitDir, workTree: work.path);
        final sha =
            git.commitTree(foreignGitDir, tree: tree, parents: [], message: 'x\n');
        work.deleteSync(recursive: true);
        git.worktreeAdd(foreignGitDir, path: stage.path, at: Commit(sha));

        expect(() => llm.refit(), throwsA(isA<WorktreeNotOurs>()));
        expect(
          File(p.join(stage.path, 'not-ours.txt')).existsSync(),
          isTrue,
          reason: 'the one destructive primitive reachable refuses what is not '
              'in the repository\'s own worktree register',
        );
      });
    });
  });

  group('upgrade — the content half', () {
    late Site site;
    late Directory downstream;
    late Entity here;
    late String hereGitDir;
    late String originGitDir;
    late _WatchedGit port;

    /// Everything runs through [port] rather than through `site.git`: the order
    /// of operations is normative, and a verb's *end state* cannot witness an
    /// order. What the watcher records is the substrate's own call sequence,
    /// which is the only place the order is observable from outside.
    Future<R> run<R>(Future<R> Function() body) => runWithGitAsync(port, body);

    setUp(() async {
      site = Site();
      port = _WatchedGit(site.git);
      downstream = site.nested('downstream');
      originGitDir = repositoryOf(site.root.path, 'bentos.llm');
      await runWithGitAsync(port, () async {
        Entity('bentos.llm', from: site.root.path).create();
        await Entity.install(originGitDir, at: downstream.path);
        here = Entity('bentos.llm', from: downstream.path);
        hereGitDir = gitDirOf(here);
      });
      port.calls.clear();
    });
    tearDown(() => site.dispose());

    /// Counts the commits this fixture has minted, so that no two of them are
    /// the same object. A commit's name is a function of its content — tree,
    /// parents, message, author — and two calls that agreed on all four minted
    /// **one** sha, so a divergence written as *they published, we authored*
    /// produced a single commit with nothing to diverge from. The counter is
    /// the divergence: two children of one parent are two commits only where
    /// they say different things.
    var minted = 0;

    /// Extends a repository's class line by one commit — the shape of somebody
    /// having published upstream. [manifest], where given, is the entity.yaml
    /// the new genesis carries, which is what step 6 re-reads.
    Commit advance(String gitDir, {String? manifest}) {
      final held = site.git.revParse(gitDir, Entity.genesisRef);
      final work = Directory.systemTemp.createTempSync('entity_upgrade_src-');
      try {
        if (manifest != null) {
          File(p.join(work.path, 'entity.yaml')).writeAsStringSync(manifest);
        }
        final tree = site.git.writeTree(gitDir, workTree: work.path);
        final sha = site.git.commitTree(
          gitDir,
          tree: tree,
          parents: [if (held != null) held.sha],
          message: 'a version published upstream (${++minted})\n',
        );
        site.git.updateRef(
          gitDir,
          ref: Entity.genesisRef,
          newCommit: Commit(sha),
          expected: held,
        );
        return Commit(sha);
      } finally {
        work.deleteSync(recursive: true);
      }
    }

    Map<String, String?> headsOf(String gitDir) => {
          for (final branch in site.git.branches(gitDir))
            branch: site.git.revParse(gitDir, 'refs/heads/$branch')?.sha,
        };

    /// Read through the site's own port. A pin is a gitlink in the
    /// superproject's index, so `Place` asks the *ambient* substrate for it —
    /// and every assertion here calls this from outside the zone, where the
    /// ambient substrate is real Git and the temp directory it is handed lies
    /// in no repository at all. `_readPin` answers `''` for that, so the reads
    /// were not weak evidence about the pin; they were a different machine's
    /// answer about a directory it had never heard of.
    String? pin() => site.run(() => Place(downstream.path).lookup(here.name)?.sha);

    File shimOf() => File(p.join(hereGitDir, ArmingTables.hookPath));

    test('the seven steps happen in the order the specification states them',
        () async {
      final published = advance(originGitDir, manifest: 'name: bentos.llm\n');
      shimOf().writeAsStringSync('#!/bin/sh\n# an older vintage\n');

      // Observed from inside the re-pin: at the instant the pin is written, the
      // fetch and the swap are behind us and the re-arm and the refit are not
      // yet done. An end-state assert cannot tell that from any other order.
      List<String> callsAtPin = const [];
      String shimAtPin = '';
      port.beforeStageGitlink = () {
        callsAtPin = List.of(port.calls);
        shimAtPin = shimOf().readAsStringSync();
      };

      final report = await run(() => here.upgrade());

      expect(report.to, published);
      expect(report.advanced, isTrue);

      expect(callsAtPin, contains('fetch'),
          reason: 'step 2 precedes the re-pin');
      expect(
        callsAtPin.where((c) => c == 'updateRef ${Entity.genesisRef}'),
        hasLength(1),
        reason: 'step 5 precedes the re-pin, and swaps genesis exactly once',
      );
      expect(
        callsAtPin.indexOf('fetch'),
        lessThan(callsAtPin.indexOf('updateRef ${Entity.genesisRef}')),
        reason: 'the line is brought down before it is adopted',
      );
      expect(
        shimAtPin,
        contains('an older vintage'),
        reason: 'step 7 is last — the apparatus is made current after the '
            'content it is derived from, never before it',
      );
      expect(shimOf().readAsStringSync(), isNot(contains('an older vintage')));
      expect(report.refit, isNotNull);
    });

    test('a remote holding nothing new reports itself as a refit', () async {
      final held = site.git.revParse(hereGitDir, Entity.genesisRef);
      final report = await run(() => here.upgrade());

      expect(report.advanced, isFalse);
      expect(report.from, held);
      expect(report.to, held);
      expect(report.refit, isNotNull,
          reason: 'the apparatus half is always performed');
      expect(
        port.calls.where((c) => c == 'updateRef ${Entity.genesisRef}'),
        isEmpty,
        reason: 'step 3 skips to 7 — a line that did not move is not swapped '
            'onto itself',
      );
      expect(pin(), held?.sha, reason: 'and the pin follows the ref it names');
    });

    test('a dry run reports what a real run would and performs nothing',
        () async {
      final published = advance(originGitDir, manifest: 'name: bentos.llm\n');
      final held = site.git.revParse(hereGitDir, Entity.genesisRef);
      final heads = headsOf(hereGitDir);
      final shim = shimOf().readAsStringSync();

      final report = await run(() => here.upgrade(dryRun: true));

      expect(report.dryRun, isTrue);
      expect(report.from, held);
      expect(report.to, published, reason: 'it reports what a real run would');
      expect(report.refit, isNull, reason: 'no refit is performed');
      expect(headsOf(hereGitDir), heads);
      expect(pin(), held?.sha);
      expect(shimOf().readAsStringSync(), shim);
    });

    test('a diverged line raises GenesisDiverged, having changed nothing',
        () async {
      // Two children of one parent: somebody published there, somebody authored
      // here. Neither line contains the other, and only a decision ends it.
      final theirs = advance(originGitDir);
      final ours = advance(hereGitDir);
      final heads = headsOf(hereGitDir);
      final pinned = pin();
      final shim = shimOf().readAsStringSync();

      await expectLater(
        run(() => here.upgrade()),
        throwsA(
          isA<GenesisDiverged>()
              .having((e) => e.local, 'local', ours)
              .having((e) => e.remote, 'remote', theirs),
        ),
      );

      expect(site.git.revParse(hereGitDir, Entity.genesisRef), ours);
      expect(headsOf(hereGitDir), heads);
      expect(pin(), pinned);
      expect(shimOf().readAsStringSync(), shim,
          reason: 'step 4 raises before step 7 is ever reached');
    });

    test('a genesis that moves between the read and the swap is contested',
        () async {
      advance(originGitDir);
      final read = site.git.revParse(hereGitDir, Entity.genesisRef);
      // The lost swap, made genuine rather than simulated: the ref moves under
      // the verb's feet after it has read, at the one seam where a concurrent
      // actor really could land — while the fetch is in flight.
      late Commit stolen;
      port.afterFetch = () => stolen = advance(hereGitDir);

      // Caught rather than matched, because a matcher evaluates its arguments
      // at CONSTRUCTION — before the future has run, and therefore before the
      // concurrent actor exists. `having(..., stolen)` read the late local at
      // the instant the expectation was built and died of
      // LateInitializationError over a refusal the verb raised exactly right.
      // The value the claim is about is only knowable afterwards, so the
      // assertion has to be made afterwards.
      Object? raised;
      try {
        await run(() => here.upgrade());
      } catch (error) {
        raised = error;
      }

      expect(raised, isA<GenesisContested>());
      final refusal = raised as GenesisContested;
      expect(refusal.expected, read);
      expect(refusal.found, stolen);

      expect(
        site.git.revParse(hereGitDir, Entity.genesisRef),
        stolen,
        reason: 'the other actor\'s line stands; a contested swap overwrites '
            'nobody',
      );
    });

    test('a re-pin that fails rolls the swap back to the value read', () async {
      advance(originGitDir);
      final read = site.git.revParse(hereGitDir, Entity.genesisRef);
      final pinned = pin();
      port.beforeStageGitlink =
          () => throw const FileSystemException('the index is not writable');

      await expectLater(
        run(() => here.upgrade()),
        throwsA(isA<FileSystemException>()),
        reason: 'the failure travels; it is not swallowed into a report',
      );

      expect(
        site.git.revParse(hereGitDir, Entity.genesisRef),
        read,
        reason: 'the pin and the ref are one act — there is no path on which '
            'this verb returns with the two disagreeing',
      );
      expect(pin(), pinned);
    });

    test('an installation carrying real instances keeps every ref but genesis',
        () async {
      // The guard's witness is an installation with instances and history, and
      // never a bare class: the destroyed channel was instance refs.
      site.run(() {
        here.instance('one').create();
        here.instance('two').create();
      });
      for (var i = 0; i < 2; i++) {
        final tip = site.git.revParse(hereGitDir, 'refs/heads/one')!;
        final work = Directory.systemTemp.createTempSync('entity_hist-');
        try {
          File(p.join(work.path, 'note')).writeAsStringSync('line $i\n');
          final tree = site.git.writeTree(hereGitDir, workTree: work.path);
          final sha = site.git.commitTree(hereGitDir,
              tree: tree, parents: [tip.sha], message: 'act $i\n');
          site.git.updateRef(hereGitDir,
              ref: 'refs/heads/one', newCommit: Commit(sha), expected: tip);
        } finally {
          work.deleteSync(recursive: true);
        }
      }

      final before = headsOf(hereGitDir);
      final published = advance(originGitDir, manifest: 'name: bentos.llm\n');

      await run(() => here.upgrade());

      final after = headsOf(hereGitDir);
      expect(after.keys.toSet(), before.keys.toSet(),
          reason: 'nothing under refs/heads/ is created or deleted');
      for (final ref in before.keys) {
        if (ref == 'genesis') continue;
        expect(after[ref], before[ref],
            reason: 'every instance ref is byte-identical across the act');
      }
      expect(after['genesis'], published.sha,
          reason: 'genesis is the only ref either verb names');
    });

    test('the installation\'s origin is refspec-free, which is what makes the '
        'fetch write no ref', () async {
      // Asserted directly rather than assumed. The premise belongs to how we
      // build installations — a bare clone sets no `remote.origin.fetch` — and
      // the day one acquires a refspec we learn it from this red, not from a
      // spurious occurrence in production. The substrate's own word on it is
      // the real-git group below; here the claim is that the fetch this verb
      // performs moves no ref of ours.
      advance(originGitDir);
      final before = headsOf(hereGitDir);
      port.afterFetch = () {
        expect(headsOf(hereGitDir), before,
            reason: 'objects only: the fetch itself writes no ref');
      };
      await run(() => here.upgrade());
    });

    test('upgrade does not scrub the remote it was handed', () async {
      final declared = site.run(() => here.remotes);
      expect(declared, hasLength(1));
      advance(originGitDir);
      await run(() => here.upgrade());
      expect(
        site.run(() => here.remotes).map((r) => (r.name, r.url)),
        declared.map((r) => (r.name, r.url)),
        reason: 'the guard describes the world rather than bending it — a '
            'write into somebody else\'s configuration to make our own check '
            'convenient is not this verb\'s business',
      );
    });
  });

  group('the skip this delivery leans on', () {
    test('dispatch mints no occurrence for a ref outside refs/heads/', () {
      // Pinned here, not only in the fetch verb it was written against: without
      // it, an upgrade on a refspec-carrying installation mints occurrences
      // whose instance is `remotes/origin/main` — an object that does not
      // exist, journaled forever and matched by every subscriber armed on `*`.
      expect(
        Dispatch.instanceOf(const TransactionRefUpdate(
          old: Commit(_oldSha),
          commit: Commit(_newSha),
          ref: 'refs/remotes/origin/main',
        )),
        isNull,
      );
      expect(
        Dispatch.instanceOf(const TransactionRefUpdate(
          old: Commit(_oldSha),
          commit: Commit(_newSha),
          ref: 'refs/tags/v1',
        )),
        isNull,
      );
      expect(
        Dispatch.instanceOf(const TransactionRefUpdate(
          old: Commit(_oldSha),
          commit: Commit(_newSha),
          ref: 'refs/heads/one',
        )),
        'one',
        reason: 'and an ordinary instance ref still is one',
      );
    });
  });

  group('the refspec premise, against the substrate itself', () {
    // FakeGit models no configuration, so it cannot witness a claim about
    // `remote.origin.fetch`. This claim is about Git, and only Git answers it.
    const git = ProcessGit();
    late Directory scratch;
    late Directory there;

    setUp(() {
      scratch = Directory(Directory.systemTemp
          .createTempSync('entity_refspec_')
          .resolveSymbolicLinksSync());
      there = Directory(p.join(scratch.path, 'there'))
        ..createSync(recursive: true);
      Directory(p.join(there.path, '.place')).createSync(recursive: true);
      File(p.join(there.path, '.place', 'place.yaml'))
          .writeAsStringSync('name: there\n');
    });
    tearDown(() {
      if (scratch.existsSync()) scratch.deleteSync(recursive: true);
    });

    String? refspecOf(String gitDir) {
      final result = Process.runSync(
        'git',
        ['--git-dir', gitDir, 'config', '--get', 'remote.origin.fetch'],
      );
      return result.exitCode == 0 ? (result.stdout as String).trim() : null;
    }

    test('install leaves no fetch refspec, and addRemote writes one', () async {
      final source = foreignRepository(
        git,
        scratch.path,
        dirName: 'source.git',
        declaredName: 't.refspec',
      );
      final installed = await Entity.install(source, at: there.path);
      final gitDir = repositoryOf(there.path, installed.name);

      expect(
        refspecOf(gitDir),
        isNull,
        reason: 'install clones bare, and a bare clone sets no '
            'remote.origin.fetch — which is why a named fetch fills FETCH_HEAD '
            'and writes no ref at all',
      );

      // The other shape, so the premise is a distinction and not a coincidence.
      final other = p.join(scratch.path, 'other.git');
      git.init(other, bare: true);
      git.addRemote(other, name: 'origin', url: source);
      expect(refspecOf(other), isNotNull,
          reason: 'a remote added by the port carries git\'s default refspec, '
              'and the same fetch then updates refs/remotes/origin/*');
    });

    test('a fresh installation can actually fetch from its own origin',
        () async {
      final source = foreignRepository(
        git,
        scratch.path,
        dirName: 'source.git',
        declaredName: 't.origin',
      );
      // No `--as`: the staged path, where the clone origin was the temp
      // directory install then deleted. This is the whole of the defect.
      final installed = await Entity.install(source, at: there.path);
      final gitDir = repositoryOf(there.path, installed.name);

      // **The material claim first.** What the config *says* is the weaker
      // half, and asserting it first would mean the falsifier never reaches
      // this line — a witness whose strongest assert is unreachable under the
      // defect it was written for.
      //
      // The claim is not what the config says — it is that the substrate can
      // use it. Before the cure this exited 128, and no assert of ours over a
      // double could have said so: a dead path is damage, and damage is
      // asserted against the substrate.
      //
      // A ref the source really holds — `refs/heads/main` is what
      // [foreignRepository] writes, and genesis is minted locally by install
      // rather than carried by the source. Asking for a ref that is not there
      // exits 128 too, which is the corpse's own code: the witness would then
      // be green on the wrong mechanism.
      final fetched = Process.runSync(
        'git',
        ['--git-dir', gitDir, 'fetch', 'origin', 'refs/heads/main'],
      );
      expect(
        fetched.exitCode,
        0,
        reason: 'git fetch origin succeeds: ${fetched.stderr}',
      );

      expect(
        git.remotes(gitDir).single.url,
        source,
        reason: 'origin names the source and not the staging directory',
      );

      expect(
        refspecOf(gitDir),
        isNull,
        reason: 'the cure is `remote set-url`, which writes the URL and '
            'nothing else — `remote add` would have left a refspec here and '
            'taken step 2\'s premise with it',
      );
    });
  });
}

const _oldSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _newSha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

/// A port that stands in front of another and **watches** — every call recorded
/// in order, with two seams a test can stand in.
///
/// It exists because two of this delivery's claims are unreachable from end
/// state: the order of operations, which is normative, and the rollback, which
/// needs a re-pin that fails for a reason the verb did not choose. [FakeGit] is
/// `final`, so the escape is delegation rather than extension.
final class _WatchedGit implements Git {
  _WatchedGit(this._inner);

  final Git _inner;

  /// Every port verb reached, in the order reached. Ref-writing verbs carry the
  /// ref, since *which* ref moved is the whole of the guard.
  final List<String> calls = [];

  /// Runs after the fetch has returned — where a concurrent actor really could
  /// land, and therefore where a lost swap is made genuine.
  void Function()? afterFetch;

  /// Runs before the pin is written. Throwing here is a re-pin that fails.
  void Function()? beforeStageGitlink;

  @override
  Future<Commit?> fetch(String gitDir,
      {required String remote, required String ref}) async {
    calls.add('fetch');
    final at = await _inner.fetch(gitDir, remote: remote, ref: ref);
    afterFetch?.call();
    return at;
  }

  @override
  void stageGitlink(String workTree,
      {required String path, required Commit at}) {
    beforeStageGitlink?.call();
    calls.add('stageGitlink $path');
    _inner.stageGitlink(workTree, path: path, at: at);
  }

  @override
  RefUpdate updateRef(String gitDir,
      {required String ref,
      required Commit newCommit,
      required Commit? expected}) {
    calls.add('updateRef $ref');
    return _inner.updateRef(gitDir,
        ref: ref, newCommit: newCommit, expected: expected);
  }

  @override
  void branch(String gitDir,
      {required String name, required Commit startPoint}) {
    calls.add('branch refs/heads/$name');
    _inner.branch(gitDir, name: name, startPoint: startPoint);
  }

  @override
  void worktreeRemove(String gitDir, {required String path}) {
    calls.add('worktreeRemove');
    _inner.worktreeRemove(gitDir, path: path);
  }

  // ------------------------------------------------------- plain forwarding

  @override
  void init(String gitDir, {bool bare = true}) =>
      _inner.init(gitDir, bare: bare);

  @override
  String hashObject(String gitDir, List<int> bytes) =>
      _inner.hashObject(gitDir, bytes);

  @override
  List<int> catFile(String gitDir, String object) =>
      _inner.catFile(gitDir, object);

  @override
  List<String> lsTree(String gitDir,
          {required Commit at, required String path}) =>
      _inner.lsTree(gitDir, at: at, path: path);

  @override
  bool isAncestor(String gitDir,
          {required Commit ancestor, required Commit descendant}) =>
      _inner.isAncestor(gitDir, ancestor: ancestor, descendant: descendant);

  @override
  String writeTree(String gitDir, {required String workTree}) =>
      _inner.writeTree(gitDir, workTree: workTree);

  @override
  String commitTree(String gitDir,
          {required String tree,
          required List<String> parents,
          required String message,
          Actor? actor}) =>
      _inner.commitTree(gitDir,
          tree: tree, parents: parents, message: message, actor: actor);

  @override
  List<String> branches(String gitDir) => _inner.branches(gitDir);

  @override
  Commit? revParse(String gitDir, String rev) => _inner.revParse(gitDir, rev);

  @override
  List<RawCommit> log(String gitDir, {required String ref, int? limit}) =>
      _inner.log(gitDir, ref: ref, limit: limit);

  @override
  RawCommit showCommit(String gitDir, Commit commit) =>
      _inner.showCommit(gitDir, commit);

  @override
  Diff diffTree(String gitDir, {required Commit from, required Commit to}) =>
      _inner.diffTree(gitDir, from: from, to: to);

  @override
  void worktreeAdd(String gitDir,
          {required String path, required Commit at}) =>
      _inner.worktreeAdd(gitDir, path: path, at: at);

  @override
  String? worktreeRepository(String path) => _inner.worktreeRepository(path);

  @override
  Commit? worktreeHead(String path) => _inner.worktreeHead(path);

  @override
  String? topLevel(String path) => _inner.topLevel(path);

  @override
  String? currentBranch(String workTree) => _inner.currentBranch(workTree);

  @override
  List<String> branchesIn(String workTree) => _inner.branchesIn(workTree);

  @override
  Commit? stagedGitlink(String workTree, String path) =>
      _inner.stagedGitlink(workTree, path);

  @override
  List<Remote> remotes(String gitDir) => _inner.remotes(gitDir);

  @override
  void addRemote(String gitDir, {required String name, required String url}) =>
      _inner.addRemote(gitDir, name: name, url: url);

  @override
  void setRemoteUrl(String gitDir,
          {required String name, required String url}) =>
      _inner.setRemoteUrl(gitDir, name: name, url: url);

  @override
  Future<void> clone(String source, String gitDir, {bool bare = true}) =>
      _inner.clone(source, gitDir, bare: bare);

  @override
  Future<void> push(String gitDir, {required String remote, String? ref}) =>
      _inner.push(gitDir, remote: remote, ref: ref);
}
