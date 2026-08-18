/// `copy` — the copy standing at a directory: stand, author, open, refit; the
/// class repository and the plot slice. Place-blind by ruling (design §1).
///
/// One type, several pages: [Copy] is composed from the slice each component
/// owns — [CopyOwn] here, [CopyEvents] in `event.dart`, [CopyFlow] in
/// `flow.dart`, [CopyPresence] in `presence.dart`.
library;

import 'dart:async';
import 'dart:io';

import 'action.dart';
import 'event.dart';
import 'flow.dart';
import 'instance.dart';
import 'manifest.dart';
import 'presence.dart';
import 'spine.dart';

/// A copy of an entity, standing at one directory.
///
/// Every method answers without the network unless its doc says otherwise.
abstract interface class Copy
    implements CopyOwn, CopyEvents, CopyFlow, CopyPresence {
  /// Bring a copy of the entity at [address] down into [at].
  ///
  /// Light by construction (R2.1.2): the declaration, the existence of every
  /// instance and each one's position arrive; no instance's content does.
  /// Contacts [address] exactly once. Throws [SourceUnreachable] if it cannot,
  /// [ManifestRefused] if the declaration cannot be read.
  static Future<Copy> stand(
    String address, {
    required Directory at,
    required Directory plot,
    Cadence? cadence,
  }) => throw UnimplementedError('Copy.stand');

  /// Author an entity that exists nowhere yet (R1.4, the rare case).
  static Future<Copy> author({
    required String name,
    required Directory at,
    required Directory plot,
    required Actor by,
    Manifest? manifest,
  }) => throw UnimplementedError('Copy.author');

  /// Open a copy that already stands at [directory]. Throws [NotACopy] if
  /// none does.
  static Copy at(Directory directory, {required Directory plot}) =>
      throw UnimplementedError('Copy.at');

  /// Read the declaration at [address] without standing anything. One
  /// contact. What an installer asks before it knows a name, and therefore
  /// before it can choose a directory or refuse a duplicate.
  static Future<Manifest> manifestAt(String address) =>
      throw UnimplementedError('Copy.manifestAt');
}

/// The slice this component owns.
abstract interface class CopyOwn {
  /// The name the manifest declares. Identity, never location (R2.5.2).
  String get name;

  /// Where this copy stands. The one copy every line of a place shares, and
  /// therefore the only thing another primitive may anchor its own layout to.
  Directory get directory;

  /// The slice of somebody else's plot this copy was given for what does not
  /// travel. Readable back; never to be walked upward from — a caller that
  /// derives its own root from `plot/..` is depending on our layout.
  Directory get plot;

  /// The declaration, read from the copy's current class state.
  Manifest get manifest;

  /// Every instance this copy knows to exist — here or at a source (R2.1.1).
  /// Answered offline, including instances whose content never came (R2.1.5).
  List<Instance> get instances;

  /// One instance by its identifier, whether or not it exists yet.
  Instance instance(String id);

  /// Which instances existed as of [when], by the dates their births carry
  /// (R2.1.6 with R2.2.3). May change after a contact brings older landings
  /// here; that change is honest and is not hidden.
  List<Instance> instancesAsOf(Instant when);

  /// The sources this copy holds, with their roles and cadence (R2.6.1).
  /// The place asks this and stores no copy of it (place R10).
  List<Source> get sources;

  /// Add, change or drop a source. Held here, and travelling nowhere: a copy
  /// stood elsewhere from the same address arrives with the manifest's
  /// defaults, not with these (R2.6.1).
  void addSource(Source source);
  void changeSource(String name, {Set<Role>? roles, Cadence? cadence});
  void dropSource(String name);

  /// Act on the class itself — the declaration and what the thing ships.
  ///
  /// The class has a line, and a line is changed only by an action: same
  /// private area, same compare-and-swap, same four outcomes, same gates as
  /// `InstanceActs.act`. A declaration is not a special kind of change; it is
  /// a change to the one file the primitive reads. A landing here publishes
  /// an event whose `instance` is null — the class itself — and is followed
  /// by a refit.
  Future<Outcome> actOnClass(
    FutureOr<void> Function(Act) body, {
    required Actor by,
    String? say,
  });

  /// Re-read the declaration and re-arm what it declares, from what stands
  /// here. Local, and never a contact.
  void refit();
}

final class SourceUnreachable implements Exception {
  const SourceUnreachable(this.address, {this.because});
  final String address;
  final String? because;
}

/// The declaration could not be read (R2.5.3). Carries the reason, because a
/// refusal that does not say why sends a person to read our source.
final class ManifestRefused implements Exception {
  const ManifestRefused(this.address, this.reason);
  final String address;
  final String reason;
}

final class NotACopy implements Exception {
  const NotACopy(this.directory);
  final Directory directory;
}
