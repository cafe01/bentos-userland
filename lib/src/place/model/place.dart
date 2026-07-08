import 'package:file/file.dart';

import '../place_resolver.dart';
import '../residence.dart';
import 'place_meta.dart';

/// A place — a directory that anchors an entity's memory and execution.
///
/// Resolved, never constructed by consumers: obtained from
/// [PlaceResolver.enclosing] or an ancestor chain. Consumers never build a
/// `.place/…` path themselves; the residence resolvers hand back the handles.
final class Place {
  Place(this._resolver, this.root, {this.isImplicit = false});

  final PlaceResolver _resolver;

  /// The place's directory.
  final Directory root;

  /// True when materialized without a `.place/` marker (the machine root, home).
  final bool isImplicit;

  PlaceMeta? _meta;

  /// Lazily-parsed metadata; a malformed `place.yaml` degrades with a warning.
  PlaceMeta get meta => _meta ??= PlaceMeta.load(root, fs: _resolver.fs);

  /// Name — the metadata's, else the directory name (else the path, for `/`).
  String get name {
    final declared = meta.name;
    if (declared != null) return declared;
    final base = _resolver.fs.path.basename(root.path);
    return base.isEmpty ? root.path : base;
  }

  String? get description => meta.description;
  String? get owner => meta.owner;

  /// The ordered ancestor chain, nearest parent → the machine root; excludes
  /// this place. Empty for a place at the machine root.
  List<Place> get ancestors => _resolver.ancestorsOf(this);

  /// Handle to [entity]'s memory store at this place. Creates nothing.
  Directory memoryRoot(String entity) =>
      Residence.memoryRoot(root, _resolver.fs, entity);

  /// Handle to [entity]'s execution state for [scope] at this place. Creates nothing.
  Directory txRoot(String entity, String scope) =>
      Residence.txRoot(root, _resolver.fs, entity, scope);
}
