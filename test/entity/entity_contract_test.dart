import 'dart:io';

import 'package:bentos_userland/entity.dart';
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
        Entity('bentos.llm', from: site.root.path).create();
        final fromRoot = Entity('bentos.llm', from: site.root.path);
        final fromDeep = Entity('bentos.llm', from: deep.path);
        expect(fromDeep.genesis, fromRoot.genesis);
      });
    });

    test('nearest wins — an installation below shadows one above', () {
      final deep = site.nested('workshop');
      site.run(() {
        Entity('bentos.llm', from: site.root.path).create();
        Entity('bentos.llm', from: deep.path).create();
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
        final e = Entity('bentos.llm', from: site.root.path).create();
        expect(e.genesis, isNotNull);
        expect(e.instances, isEmpty);
      });
    });

    test('genesis is never listed among the instances', () {
      site.run(() {
        final e = Entity('bentos.llm', from: site.root.path).create();
        e.instance('s1').create();
        expect(
          e.instances.map((i) => i.id),
          ['s1'],
          reason: 'genesis is the structure instances are born from, not one',
        );
      });
    });
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
        Entity('bentos.llm', from: site.root.path).create();
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
        Entity('bentos.llm', from: site.root.path).create();
        Entity('bentos.llm', from: downstream.path).create();
        Entity('bentos.llm', from: downstream.path).instance('s1').create();
        expect(
          Entity('bentos.llm', from: site.root.path).instances,
          isEmpty,
          reason: 'refs belong to the installation until they are pushed',
        );
      });
    });
  });
}
