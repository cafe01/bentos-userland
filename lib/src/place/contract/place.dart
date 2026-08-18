/// `place` — the marker, the card, the handle law and the lines (R1–R4,
/// R23–R26, R28). Inherits the built spatial half's law: a handle is obtained
/// *at* the anchor and *to* the enclosing marked root; walk up only; the
/// machine root and the home stand as implicit places even unmarked.
library;

import 'dart:io';

import '../../entity/contract/contract.dart';
import 'arrangement.dart';
import 'record.dart';

Never _todo(String member) => throw UnimplementedError('Place.$member');

/// A place — a marked directory, the WHERE primitive. A peer of [File] and
/// [Directory]: the class is the API. Every member re-derives on access.
final class Place {
  Place(this.anchorPath);

  /// The anchor: surfaced by no member; every member speaks of the referent.
  final String anchorPath;

  static Place get current => _todo('current');

  /// The referent: the nearest enclosing marked directory, walking up.
  Directory get root => _todo('root');
  bool get isImplicit => _todo('isImplicit');

  /// Walk up only. A line stood elsewhere is the same place seen twice: its
  /// `parent` is the place's parent, never the place.
  Place? get parent => _todo('parent');
  List<Place> get ancestors => _todo('ancestors');

  /// R2 — read from the arrangement's tree at the line in view.
  Card get card => _todo('card');

  /// Genesis: mark the anchor, author the arrangement copy at it, birth the
  /// first line, land the card and the lineage as the first action, signed.
  /// Inside a marked place a second landing records the room in that
  /// place's arrangement (R6); the two are not one transaction.
  ///
  /// [source] is the arrangement's own first source, when the place is born
  /// with one (R34); absent, the place has no source yet and says so.
  Future<Place> create({required Actor actor, String? name, String? description, String? owner, Source? source}) =>
      _todo('create');

  /// R33 — stand a place here from an address: the arrangement copy comes
  /// down light, the default line is made present at [at], and nothing of
  /// any thing's mass moves. `Arrangement.materialize` stands things and
  /// rooms light afterwards.
  static Future<Place> carry(String address, {required Directory at}) => _todo('carry');

  /// The one generic gate to private ground (R35). Single path segment;
  /// opaque; ignored by the arrangement's tree; never travels. Anchored to
  /// the arrangement copy's directory, so every line shares one plot.
  Directory plot(String namespace) => _todo('plot');
  List<String> get plots => _todo('plots');

  /// The record at the line in view (sync: files at this root), and as of an
  /// instant (R27) — a read at a point, and therefore a `Future`.
  Arrangement get arrangement => _todo('arrangement');
  Future<Arrangement> asOf(DateTime instant) => _todo('asOf');

  /// The line this root is a materialization of.
  Line get line => _todo('line');

  /// Every line, here or known at a source — the arrangement copy's
  /// instances, by name.
  List<Line> get lines => _todo('lines');

  /// Fork: birth a new arrangement instance from [from] (default: the line in
  /// view) at its tip, or at its point as of [asOf]. Copies the record and
  /// never the mass (R24). One landing, signed.
  Future<Line> fork(String name, {required Actor actor, Line? from, DateTime? asOf}) => _todo('fork');

  /// Stand a line as a place root of its own (R25). Default address:
  /// `plot('place')/lines/<name>`; any directory may be given.
  Future<Place> stand(Line line, {Directory? at}) => _todo('stand');

  /// Which lines stand where, read from the copy's materializations (R13).
  Map<Line, Set<Directory>> get stood => _todo('stood');

  /// The record of this place at [line], for a caller that has not stood it.
  /// A read at the ref (entity R2.2.2): makes nothing present.
  Future<Arrangement> at(Line line) => _todo('at');
}
