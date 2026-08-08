import 'package:path/path.dart' as p;

import '../place/place.dart';
import 'arming/arming.dart';
import 'arming/arming_provenance.dart';
import 'entity.dart';
import 'event.dart';
import 'manifest.dart';
import '../git/git_ambient.dart';
import '../git/model/commit.dart';

/// The installation's life after its constructor — `refit` and `upgrade`.
///
/// **Declarations only.** Every body here throws [UnimplementedError]: this file
/// is the design chair's contract in literal Dart, landed so that the suite
/// written against it compiles and fails naming its own missing member. The
/// builder fills the bodies and writes no signature.
///
/// The normative account is the design specification at
/// `domain/bentos/entity/installation/design-specification`.

// ---------------------------------------------------------------- the reports

/// The report of a refit — what the act found and what it changed.
final class RefitReport {
  const RefitReport({required this.shim, required this.stagedAt});

  /// Where the shim was written. Always written: the coreutil is its only
  /// author, so its previous content and vintage are never consulted.
  final String shim;

  /// The commit the class tree now stands at, or null where this installation
  /// holds no genesis and there is therefore no tree to stand up.
  final Commit? stagedAt;
}

/// The report of an upgrade. Every field states what *this act* did, so a no-op
/// upgrade is legible as a no-op rather than as a success with no detail.
final class UpgradeReport {
  const UpgradeReport({
    required this.from,
    required this.to,
    required this.armed,
    required this.refit,
    required this.dryRun,
  });

  /// The genesis this installation held. Null where it held none.
  final Commit? from;

  /// The genesis it holds now — equal to [from] when the remote had nothing.
  final Commit to;

  /// The manifest-provenance lines that now stand. Replaced wholesale, so this
  /// is the count after and not a delta.
  final List<Registration> armed;

  /// The apparatus half, always performed. Null on a dry run.
  final RefitReport? refit;

  final bool dryRun;

  /// Whether the entity's line actually moved.
  bool get advanced => from != to;
}

// ---------------------------------------------------------------- the verbs

extension InstallationLife on Entity {
  /// Makes this installation's **apparatus** current: the shim rewritten from
  /// the running coreutil, the class tree re-staged at the genesis already held.
  ///
  /// Synchronous, and that is a guarantee rather than an implementation note:
  /// this verb reaches no network, reads no remote, and requires none to be
  /// declared.
  ///
  /// It writes no ref, moves no place pin, and changes no line in any arming
  /// table. Those belong to [InstallationUpgrade.upgrade] because they are
  /// derived from content, and content is what this verb does not touch.
  ///
  /// Idempotent: twice in succession leaves the installation byte-identical to
  /// once, tables included.
  ///
  /// Throws [EntityNotInstalled] where the walk answers nothing, and
  /// `WorktreeNotOurs` where the stage directory holds content this repository
  /// never registered — never discarding it.
  RefitReport refit() {
    final gitDir = gitDirOf(this);
    // Both halves are already idempotent and already the only authors of what
    // they write, which is the whole reason this verb is composition and not
    // machinery: arming rewrites the shim from the running coreutil without
    // consulting what stood there, and the stage follows `genesis` — so a tree
    // that fell behind and one that was never put down are the same question.
    ArmingTables(gitDir, entity: name).ensureArmed();
    stagedClass.refresh();
    return RefitReport(
      shim: p.join(gitDir, ArmingTables.hookPath),
      stagedAt: ambientGit.revParse(gitDir, Entity.genesisRef),
    );
  }
}

extension InstallationUpgrade on Entity {
  /// Brings this installation's **content** forward: fetch from the remote
  /// already declared, advance `genesis`, re-pin the place's gitlink, replace
  /// the manifest-provenance arming lines, and then refit.
  ///
  /// Takes no source: pointing an installation at a different origin is a
  /// re-founding and wears `install`'s risk, not this verb's.
  ///
  /// [dryRun] reports exactly what a real run would report and performs nothing
  /// — no fetch, no advance, no re-pin, no re-arm, no refit.
  ///
  /// Asynchronous: it crosses the network.
  ///
  /// Throws [NoRemoteDeclared] where the installation has no origin,
  /// [GenesisNotAtRemote] where the remote holds no genesis,
  /// [GenesisContested] where the ref moved between read and swap, and
  /// [GenesisDiverged] where the fetched line is not a descendant of the one
  /// held.
  Future<UpgradeReport> upgrade({bool dryRun = false}) async {
    // 1 — the installation, and the genesis it holds. Read as a nullable: the
    // `genesis` getter throws where this verb contemplates none.
    final gitDir = gitDirOf(this);
    final placeRoot = placeOf(this);
    final held = ambientGit.revParse(gitDir, Entity.genesisRef);

    final declared = ambientGit.remotes(gitDir);
    if (declared.isEmpty) throw NoRemoteDeclared(name);
    final remote = declared
        .firstWhere((r) => r.name == 'origin', orElse: () => declared.first);

    // 2 — the class line, objects only. The installation's origin is
    // refspec-free by construction, which is what makes this write no ref.
    final arrived = await ambientGit.fetch(
      gitDir,
      remote: remote.name,
      ref: Entity.genesisRef,
    );
    if (arrived == null) {
      throw GenesisNotAtRemote(name, remote: remote.name);
    }

    final tables = ArmingTables(gitDir, entity: name);
    List<Registration> standingManifestLines() =>
        [for (final r in tables.all) if (r.provenance == Provenance.manifest) r];

    // 3 — a line that did not move is not swapped onto itself: the act is a
    // refit and reports itself as one.
    if (arrived == held) {
      return UpgradeReport(
        from: held,
        to: arrived,
        armed: standingManifestLines(),
        refit: dryRun ? null : refit(),
        dryRun: dryRun,
      );
    }

    // 4 — two lines from a common ancestor. Nothing was refused and nothing
    // moved; only a decision ends it.
    if (held != null &&
        !ambientGit.isAncestor(gitDir, ancestor: held, descendant: arrived)) {
      throw GenesisDiverged(local: held, remote: arrived);
    }

    if (dryRun) {
      return UpgradeReport(
        from: held,
        to: arrived,
        armed: standingManifestLines(),
        refit: null,
        dryRun: true,
      );
    }

    // 5 — the swap, against the value read at step 1.
    final swap = ambientGit.updateRef(
      gitDir,
      ref: Entity.genesisRef,
      newCommit: arrived,
      expected: held,
    );
    if (!swap.moved) {
      throw GenesisContested(
        expected: held,
        found: ambientGit.revParse(gitDir, Entity.genesisRef),
      );
    }

    // 6 — the pin and the ref are one act. A genesis that moved while the pin
    // did not means the place's tree lies about what stands in it, so the swap
    // is rolled back to the value read and the failure travels.
    final List<Registration> armed;
    try {
      Place(placeRoot).pin(name, arrived.sha);
      // An entity that declares nothing declares no reactions, and a line that
      // carries no manifest at all is the ordinary condition of one authored
      // and never written into — not a fault to roll a good upgrade back on.
      Manifest? carried;
      try {
        carried = manifest;
      } on Object {
        carried = null;
      }
      armed = tables.replaceProvenance(
        Provenance.manifest,
        declared: carried == null
            ? const []
            : declaredArmings(carried, entity: name, placeRoot: placeRoot),
      );
    } on Object {
      // Where this installation held no genesis there is nothing to roll back
      // *to*: undoing the swap would be deleting the ref, and the port offers
      // no verb for it. The window is real and it is the first installation's
      // only, which is why it is named here rather than hidden.
      if (held != null) {
        ambientGit.updateRef(
          gitDir,
          ref: Entity.genesisRef,
          newCommit: held,
          expected: arrived,
        );
      }
      rethrow;
    }

    // 7 — the apparatus, after the content it is derived from.
    return UpgradeReport(
      from: held,
      to: arrived,
      armed: armed,
      refit: refit(),
      dryRun: false,
    );
  }
}

// ---------------------------------------------------------------- the refusals

/// The installation declares no origin, so there is nothing to bring forward.
///
/// An absence and never a refusal: nothing was refused, and the thing named is
/// simply not there.
final class NoRemoteDeclared implements Exception {
  const NoRemoteDeclared(this.entity);

  final String entity;

  @override
  String toString() => 'no remote declared: $entity — '
      "publish it to give it an origin, or refit to bring the apparatus "
      'current without a network';
}

/// The declared remote holds no genesis — the class-level twin of
/// `InstanceNotAtRemote`, and classified identically.
final class GenesisNotAtRemote implements Exception {
  const GenesisNotAtRemote(this.entity, {required this.remote});

  final String entity;
  final String remote;

  @override
  String toString() => 'no genesis at remote: $entity ($remote)';
}

/// `genesis` moved between the read and the swap. Retrying, having re-read,
/// terminates.
final class GenesisContested implements Exception {
  const GenesisContested({required this.expected, required this.found});

  final Commit? expected;
  final Commit? found;

  @override
  String toString() => 'genesis contested: expected '
      '${expected?.sha ?? 'none'}, found ${found?.sha ?? 'none'}';
}

/// The fetched line and the held line advanced from a common ancestor. Nothing
/// was refused and nothing moved; only a decision ends it.
final class GenesisDiverged implements Exception {
  const GenesisDiverged({required this.local, required this.remote});

  final Commit local;
  final Commit remote;

  @override
  String toString() =>
      'genesis diverged: local ${local.sha}, remote ${remote.sha}';
}
