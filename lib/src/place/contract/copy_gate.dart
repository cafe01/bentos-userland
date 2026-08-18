/// The one gate through which the place enters the entity (design §laws).
/// The four static entry points of `Copy`, read as a zone-scoped ambient with
/// the entity as its default — the seam the design suite fakes. A `Copy` once
/// in hand is an object and is faked as one.
library;

import 'dart:async';
import 'dart:io';

import '../../entity/contract/contract.dart';

const Symbol copyGateKey = #bentos.place.copyGate;

abstract interface class CopyGate {
  /// `Copy.stand`, light: declaration and positions, no content.
  Future<Copy> stand(String address, {required Directory at, required Directory plot});

  /// `Copy.author`, the rare case: an entity that exists nowhere yet.
  Future<Copy> author(Manifest manifest, {required Directory at, required Directory plot, required Actor actor});

  /// `Copy.at`: the copy standing at [at] — or, when [at] is a directory the
  /// copy holds a materialization at, that copy. Throws [NotACopy] otherwise.
  Copy at(Directory at, {required Directory plot});

  /// `Copy.manifestAt`: one contact, nothing stood.
  Future<Manifest> manifestAt(String address);
}

/// The gate in force: the one installed in the zone, or the entity itself.
CopyGate get copyGate =>
    (Zone.current[copyGateKey] as CopyGate?) ?? const _EntityGate();

final class _EntityGate implements CopyGate {
  const _EntityGate();
  @override
  Future<Copy> stand(String address, {required Directory at, required Directory plot}) =>
      Copy.stand(address, at: at, plot: plot);
  @override
  Future<Copy> author(Manifest manifest, {required Directory at, required Directory plot, required Actor actor}) =>
      Copy.author(name: manifest.name, at: at, plot: plot, by: actor, manifest: manifest);
  @override
  Copy at(Directory at, {required Directory plot}) => Copy.at(at, plot: plot);
  @override
  Future<Manifest> manifestAt(String address) => Copy.manifestAt(address);
}
