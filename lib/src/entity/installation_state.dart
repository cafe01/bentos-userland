import 'dart:io';

import 'package:path/path.dart' as p;

import '../place/place.dart';
import 'arming/arming.dart';
import 'entity.dart';
import '../git/git_ambient.dart';

/// **What actually stands, at one place, for one name.**
///
/// Installing writes five separate facts, in order, and until this page existed
/// the whole system read one of them — the `.gitmodules` line — and called the
/// answer *installed*. That is why a crash mid-install left a site that could
/// neither be used nor installed over: the record said yes, the world said no,
/// and nothing could say which.
///
/// **Facts, never a verdict.** Every field is asked of the disk at the moment
/// it is read, and each is separately reportable, because the cure differs per
/// fact and a caller told only *incomplete* is told nothing it can act on.
///
/// This is a **local** reading: no remote is reached and none need be declared.
final class InstallationState {
  const InstallationState({
    required this.name,
    required this.place,
    required this.repository,
    required this.genesis,
    required this.registered,
    required this.pinnable,
    required this.pinned,
    required this.armed,
    required this.staged,
  });

  /// The name asked about, and the place it was asked of. A state without its
  /// vantage is unactionable, the same way `EntityNotInstalled` reports both.
  final String name;
  final String place;

  /// **1 — the repository.** A bare repository stands in the place's plot.
  final bool repository;

  /// **2 — the line.** That repository holds a `genesis` ref. A clone that
  /// arrived and was never given one is a repository with no class in it.
  final bool genesis;

  /// **3 — the registration.** The place's `.gitmodules` names it. This alone
  /// is what the installed/not-installed question used to read.
  final bool registered;

  /// **4 — the pin**, and whether one is even possible here. A place lying in
  /// no repository has no index to hold a gitlink, so an absent pin there is
  /// the ordinary condition and not a defect — [complete] reads [pinnable]
  /// before it reads [pinned], and a report that omitted this distinction
  /// would call every place outside a repository half-installed forever.
  final bool pinnable;
  final bool pinned;

  /// **5 — the apparatus.** The shim stands in the repository's hooks, and the
  /// class's tree stands beside it. `refit` is the cure for both, which is why
  /// they are reported and not repaired here.
  final bool armed;
  final bool staged;

  /// Nothing of ours stands here at all — the state a fresh `install` requires
  /// and the state a rolled-back one restores.
  bool get absent =>
      !repository && !registered && !pinned && !armed && !staged;

  /// Every fact this place can hold is true.
  bool get complete =>
      repository && genesis && registered && (!pinnable || pinned) && armed && staged;

  /// Something stands and something does not — the state install must never
  /// leave behind, and the only state whose report has to be a sentence.
  bool get partial => !absent && !complete;

  /// The facts that are missing, named as this file names them — what a
  /// refusal prints so that the operator reads *what is wrong* rather than
  /// *that something is*.
  List<String> get missing => [
        if (!repository) 'repository',
        if (repository && !genesis) 'genesis',
        if (!registered) 'registration',
        if (pinnable && !pinned) 'pin',
        if (!armed) 'arming',
        if (!staged) 'class tree',
      ];

  /// The facts that stand, for the mirror sentence: a partial install has to
  /// report both halves or the reader cannot tell it from a fresh site.
  List<String> get standing => [
        if (repository) 'repository',
        if (genesis) 'genesis',
        if (registered) 'registration',
        if (pinned) 'pin',
        if (armed) 'arming',
        if (staged) 'class tree',
      ];

  @override
  String toString() => 'installation $name at $place: '
      '${absent ? 'absent' : complete ? 'complete' : 'partial — '
          'standing ${standing.join(', ')}; missing ${missing.join(', ')}'}';

  /// Reads the five facts **at one named place** — never the walk up the tree.
  ///
  /// The walk answers *which installation does this name resolve to*, which is
  /// a different question and the wrong one here: `install` acts on the place
  /// it was pointed at, and a predicate that resolved upward would report the
  /// parent's healthy installation while the child's half-built one is the
  /// thing standing in the way.
  static InstallationState read(Place place, String name) {
    final gitDir =
        p.join(place.plot(Entity.plotNamespace).path, name, Entity.repositoryDirName);
    final repository = Directory(gitDir).existsSync();
    final record = place.lookup(name);
    return InstallationState(
      name: name,
      place: place.root.path,
      repository: repository,
      genesis:
          repository && ambientGit.revParse(gitDir, Entity.genesisRef) != null,
      registered: record != null,
      pinnable: place.superproject != null,
      pinned: record != null && record.sha.isNotEmpty,
      armed: repository && File(p.join(gitDir, ArmingTables.hookPath)).existsSync(),
      staged: Directory(
        p.join(place.plot(Entity.plotNamespace).path, name, Entity.classDirName),
      ).existsSync(),
    );
  }
}
