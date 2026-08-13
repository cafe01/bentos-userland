import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers.dart';

/// **Tier A — the contract.** Behaviour over the public surface, against the
/// `FakeGit` port. Red today by construction: the bodies throw
/// [UnimplementedError], and this suite is what turns green when they stop —
/// **without one assertion being edited.** An assert changed during
/// construction is construction rewriting its own acceptance.
void main() {
  late Site site;

  setUp(() => site = Site());
  tearDown(() => site.dispose());

  group('the handle law', () {
    test('a handle is cheap, creates nothing, and touches no disk', () {
      final before = site.root.listSync().length;
      site.run(() => Entity('bentos.llm', from: site.root.path));
      expect(site.root.listSync().length, before);
      expect(site.git.repos, isEmpty);
    });

    test('a handle to an uninstalled name is legal until it is read', () {
      final handle = site.run(() => Entity('nobody.here', from: site.root.path));
      expect(handle.name, 'nobody.here');
      expect(
        () => site.run(() => handle.instances),
        throwsA(isA<EntityNotInstalled>()),
        reason: 'resolution fails at the read, never at the mint',
      );
    });

    test('two handles anchored at different depths speak of one installation', () {
      final deep = site.nested('workshop');
      site.run(() {
        Entity('bentos.llm', from: site.root.path).create(actor: testActor);
        final fromRoot = Entity('bentos.llm', from: site.root.path);
        final fromDeep = Entity('bentos.llm', from: deep.path);
        expect(fromDeep.genesis, fromRoot.genesis);
      });
    });

    test('nearest wins — an installation below shadows one above', () {
      final deep = site.nested('workshop');
      site.run(() {
        Entity('bentos.llm', from: site.root.path).create(actor: testActor);
        Entity('bentos.llm', from: deep.path).create(actor: testActor);
        expect(
          Entity('bentos.llm', from: deep.path).genesis,
          isNot(Entity('bentos.llm', from: site.root.path).genesis),
          reason: 'two installations are two participants, never two views',
        );
      });
    });
  });

  group('genesis', () {
    test('a created entity has genesis and no instances', () {
      site.run(() {
        final e = Entity('bentos.llm', from: site.root.path).create(actor: testActor);
        expect(e.genesis, isNotNull);
        expect(e.instances, isEmpty);
      });
    });

    test('genesis is never listed among the instances', () {
      site.run(() {
        final e = Entity('bentos.llm', from: site.root.path).create(actor: testActor);
        e.instance('s1').create();
        expect(
          e.instances.map((i) => i.id),
          ['s1'],
          reason: 'genesis is the structure instances are born from, not one',
        );
      });
    });
  });

  group('birth', () {
    // Birth is a compare-and-swap at the ref — `expected: null`, which the
    // substrate reads as *this must not exist*. What that buys is the case
    // below it: several actors arriving at one instant, which is ordinary for
    // anything an external will enters through, and which read-then-create
    // could only ever lose.
    test('a name already born refuses the deliberate birth, in the ontology\'s '
        'own words', () {
      site.run(() {
        final e = Entity('bentos.llm', from: site.root.path).create(actor: testActor);
        e.instance('s1').create();
        expect(
          () => e.instance('s1').create(),
          throwsA(isA<InstanceExists>()),
          reason: 'a caller that typed the constructor asked to MAKE one, and '
              'did not — and it hears that from this ontology rather than as '
              "git's own `cannot lock ref`, which names a mechanism the caller "
              'never used',
        );
      });
    });

    test('ensureBorn is idempotent, and says who did the birthing', () {
      site.run(() {
        final e = Entity('bentos.llm', from: site.root.path).create(actor: testActor);
        final instance = e.instance('s1');
        expect(instance.ensureBorn(), isTrue, reason: 'nobody had');
        final born = instance.tip;
        expect(instance.ensureBorn(), isFalse, reason: 'somebody already had');
        expect(
          instance.tip,
          born,
          reason: 'the second call moved nothing: losing the birth race and '
              'never having run it are the same world',
        );
      });
    });

    // **The race itself is not witnessed here, and this file cannot witness
    // it**: one process, one `FakeGit`, and no way to interleave two callers
    // between the read and the swap — a green obtained by serialization reads
    // exactly like the strong kind. What quantifies over the isolation
    // boundary is the storm, in
    // `test/chat/material/storm_material_test.dart`: four operating-system
    // processes joining an unborn channel at one instant.
  });

  group('the repository is not on the surface', () {
    test('the API exposes no git directory', () {
      final surface = Entity('x', from: site.root.path) as dynamic;
      expect(
        () => surface.gitDir,
        throwsA(isA<NoSuchMethodError>()),
        reason: 'a caller holding a repository runs git itself, past the swap',
      );
    });
  });

  group('install', () {
    test('brings a copy into another place and does not materialize it', () async {
      final downstream = site.nested('downstream');

      await site.runAsync(() async {
        Entity('bentos.llm', from: site.root.path).create(actor: testActor);
        final source = repositoryOf(site.root.path, 'bentos.llm');

        final here = await Entity.install(source, at: downstream.path);
        expect(here.name, 'bentos.llm');
        expect(
          Directory('${downstream.path}/bentos.llm').existsSync(),
          isFalse,
          reason: 'a site that only reacts holds no worktree at all',
        );
      });
    });

    test('two installations of one entity are two participants', () {
      final downstream = site.nested('downstream');
      site.run(() {
        Entity('bentos.llm', from: site.root.path).create(actor: testActor);
        Entity('bentos.llm', from: downstream.path).create(actor: testActor);
        Entity('bentos.llm', from: downstream.path).instance('s1').create();
        expect(
          Entity('bentos.llm', from: site.root.path).instances,
          isEmpty,
          reason: 'refs belong to the installation until they are pushed',
        );
      });
    });
  });

  group('materializedAt', () {
    test('unmaterialized answers absence, never a throw', () {
      site.run(() {
        final e = Entity('bentos.llm', from: site.root.path).create(actor: testActor);
        expect(e.materializedAt, isNull);
      });
    });

    test('materialized answers the installation\'s own path', () {
      site.run(() {
        final e = Entity('bentos.llm', from: site.root.path).create(actor: testActor);
        final where = p.join(site.root.path, e.name);

        e.materialize(e.genesis, path: where);

        expect(e.materializedAt?.path, where);
      });
    });

    test('the path it answers is the one refresh() actually moves', () async {
      await site.runAsync(() async {
        final e = Entity('bentos.mem', from: site.root.path).create(actor: testActor);
        final instance = e.instance('main')..create();
        final where = p.join(site.root.path, e.name);
        instance.materialize(at: where);
        expect(e.materializedAt?.path, where);

        await instance.act('write', (w) {
          File(p.join(w.directory.path, 'f.txt')).writeAsStringSync('x');
        }, actor: testActor);
        final result = instance.materialization(e.materializedAt!.path).refresh();

        expect(result.moved, isTrue);
        expect(File(p.join(e.materializedAt!.path, 'f.txt')).readAsStringSync(), 'x');
      });
    });
  });
}
