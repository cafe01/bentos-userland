import 'dart:io';

import 'package:bentos_userland/entity.dart';
// The predicate is read at a **named** place, so the test names one — the same
// reach `entity install` makes, one floor below its own resolution.
import 'package:bentos_userland/src/place/place.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../git/fake_git.dart';
import 'helpers.dart';

/// **What stands, and what a constructor leaves behind when it throws.**
///
/// Two claims, and they are one subject: an install is five facts written in
/// order, so a failure between them is a state — and until a reader could name
/// that state, *installed* was one boolean and the site was unusable in a way
/// nothing could describe.
void main() {
  late Site site;

  setUp(() => site = Site('state'));
  tearDown(() => site.dispose());

  /// The installation's own directory inside the plot.
  String plotOf(String name) =>
      p.join(site.root.path, '.place', Entity.plotNamespace, name);

  InstallationState stateOf(String name) =>
      site.run(() => InstallationState.read(Place(site.root.path), name));

  group('the completeness predicate', () {
    test('names nothing at a place where nothing was installed', () {
      final state = stateOf('t.absent');

      expect(state.absent, isTrue);
      expect(state.complete, isFalse);
      expect(state.partial, isFalse,
          reason: 'empty ground is not a half-installation');
    });

    test('a whole installation reports every fact standing', () {
      site.run(() => Entity('t.whole', from: site.root.path).create(actor: testActor));

      final state = stateOf('t.whole');

      expect(state.repository, isTrue);
      expect(state.genesis, isTrue);
      expect(state.registered, isTrue);
      expect(state.pinned, isTrue);
      expect(state.armed, isTrue);
      expect(state.staged, isTrue);
      expect(state.complete, isTrue);
      expect(state.missing, isEmpty);
    });

    test('each fact is separately reportable, because each has its own cure',
        () {
      site.run(() => Entity('t.half', from: site.root.path).create(actor: testActor));
      // The apparatus, removed the way a crash removes it: the bytes go, the
      // record stays. This is the state `refit` exists for.
      File(p.join(plotOf('t.half'), Entity.repositoryDirName, 'hooks',
              'reference-transaction'))
          .deleteSync();

      final state = stateOf('t.half');

      expect(state.partial, isTrue);
      expect(state.missing, ['arming']);
      expect(state.standing, contains('registration'));
    });

    test('a registration with no repository is partial, not installed', () {
      site.run(() => Place(site.root.path)
          .register('t.ghost', url: 'nowhere', path: 't.ghost', sha: 'a' * 40));

      final state = stateOf('t.ghost');

      expect(state.registered, isTrue, reason: 'the one fact the old bar read');
      expect(state.repository, isFalse);
      expect(state.partial, isTrue);
      expect(state.missing, contains('repository'));
    });

    test('a place outside any repository is not called half-installed forever',
        () {
      // No pin is possible where there is no index. Reported as *no pin can be
      // held here* and never as *the pin is missing*.
      final loose = Site('loose')..git.workTrees.clear();
      addTearDown(loose.dispose);
      loose.run(() => Entity('t.loose', from: loose.root.path).create(actor: testActor));

      final state =
          loose.run(() => InstallationState.read(Place(loose.root.path), 't.loose'));

      expect(state.pinnable, isFalse);
      expect(state.pinned, isFalse);
      expect(state.complete, isTrue);
    });
  });

  group('a constructor that throws leaves nothing of its own behind', () {
    /// A source to install from, born of `create` at another site.
    String sourceNamed(String name, Site origin) {
      origin.run(() => Entity(name, from: origin.root.path).create(actor: testActor));
      return repositoryOf(origin.root.path, name);
    }

    test('a failure at the pin rolls the clone and the registration back',
        () async {
      final origin = Site('origin', site.git);
      addTearDown(origin.dispose);
      final source = sourceNamed('t.rolled', origin);
      // The reported failure, installed as a seam: `update-index --cacheinfo`
      // refusing over tracked files is a throw from inside `register`, after
      // the clone and after the `.gitmodules` line.
      site.git.failStageGitlink = true;

      await expectLater(
        site.runAsync(() =>
            Entity.install(source, at: site.root.path, as: 't.rolled')),
        throwsA(isA<Exception>()),
      );

      final state = stateOf('t.rolled');
      expect(state.absent, isTrue, reason: state.toString());
      expect(Directory(plotOf('t.rolled')).existsSync(), isFalse);
      expect(
        File(p.join(site.root.path, '.gitmodules')).existsSync()
            ? File(p.join(site.root.path, '.gitmodules')).readAsStringSync()
            : '',
        isNot(contains('t.rolled')),
      );
    });

    test('the rolled-back name installs cleanly on the next attempt', () async {
      final origin = Site('origin2', site.git);
      addTearDown(origin.dispose);
      final source = sourceNamed('t.retry', origin);
      site.git.failStageGitlink = true;
      await site
          .runAsync(
              () => Entity.install(source, at: site.root.path, as: 't.retry'))
          .then<Object?>((_) => null, onError: (Object e) => e);

      // The whole point of rolling back: the second attempt is a first attempt.
      site.git.failStageGitlink = false;
      final installed = await site.runAsync(
          () => Entity.install(source, at: site.root.path, as: 't.retry'));

      expect(installed.name, 't.retry');
      expect(stateOf('t.retry').complete, isTrue);
    });

    test('it undoes only what it created — a foreign installation survives',
        () async {
      final origin = Site('origin3', site.git);
      addTearDown(origin.dispose);
      final source = sourceNamed('t.neighbour', origin);
      // Somebody else's installation, whole, standing at the same place.
      site.run(() =>
          Entity('t.standing', from: site.root.path).create(actor: testActor));
      site.git.failStageGitlink = true;

      await site
          .runAsync(() =>
              Entity.install(source, at: site.root.path, as: 't.neighbour'))
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect(stateOf('t.standing').complete, isTrue,
          reason: 'the undo is this call\'s own writes and nobody else\'s');
      expect(stateOf('t.neighbour').absent, isTrue);
    });
  });

  group('the bar an operator meets', () {
    test('a whole installation is refused as already installed', () async {
      final origin = Site('origin4', site.git);
      addTearDown(origin.dispose);
      origin.run(
          () => Entity('t.twice', from: origin.root.path).create(actor: testActor));
      final source = repositoryOf(origin.root.path, 't.twice');
      await site.runAsync(
          () => Entity.install(source, at: site.root.path, as: 't.twice'));

      final said = await site
          .runAsync(() =>
              Entity.install(source, at: site.root.path, as: 't.twice'))
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect(said, isA<EntityAlreadyInstalled>());
      expect(said.toString(), contains('already installed'));
    });

    test('a half-installation says which facts are missing, and does not resume',
        () async {
      final origin = Site('origin5', site.git);
      addTearDown(origin.dispose);
      origin.run(
          () => Entity('t.partial', from: origin.root.path).create(actor: testActor));
      final source = repositoryOf(origin.root.path, 't.partial');
      await site.runAsync(
          () => Entity.install(source, at: site.root.path, as: 't.partial'));
      // A crash below us, or an older vintage of this code: the repository is
      // gone and the record stands.
      Directory(p.join(plotOf('t.partial'), Entity.repositoryDirName))
          .deleteSync(recursive: true);

      final said = await site
          .runAsync(() =>
              Entity.install(source, at: site.root.path, as: 't.partial'))
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect(said, isA<EntityAlreadyInstalled>());
      final sentence = said.toString();
      expect(sentence, contains('half-installed'));
      expect(sentence, contains('repository'),
          reason: 'the missing fact is named, not merely counted');
      expect(sentence, contains('registration'),
          reason: 'and what still stands, or the reader cannot tell the state');
      expect(sentence, isNot(contains('refit')),
          reason: 'refit does not restore a repository, and may not be offered');
    });

    test('create meets the same bar — a name already standing is refused',
        () {
      site.run(
          () => Entity('t.authored', from: site.root.path).create(actor: testActor));

      expect(
        () => site.run(() => Entity('t.authored', from: site.root.path)
            .create(actor: testActor)),
        throwsA(isA<EntityAlreadyInstalled>()),
      );
    });
  });

  group('create leaves nothing of its own behind on a throw', () {
    test('a failure at the pin rolls the init and the registration back', () {
      site.git.failStageGitlink = true;

      expect(
        () => site
            .run(() => Entity('t.half-born', from: site.root.path)
                .create(actor: testActor)),
        throwsA(isA<Exception>()),
      );

      final state = stateOf('t.half-born');
      expect(state.absent, isTrue, reason: state.toString());
      expect(Directory(plotOf('t.half-born')).existsSync(), isFalse);
    });

    test('the rolled-back name creates cleanly on the next attempt', () {
      site.git.failStageGitlink = true;
      try {
        site.run(() =>
            Entity('t.born-retry', from: site.root.path).create(actor: testActor));
      } on Object {
        // Expected — the point of this test is what happens after.
      }

      site.git.failStageGitlink = false;
      final created = site.run(() =>
          Entity('t.born-retry', from: site.root.path).create(actor: testActor));

      expect(created.name, 't.born-retry');
      expect(stateOf('t.born-retry').complete, isTrue);
    });
  });
}
