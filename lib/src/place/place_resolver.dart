import 'package:file/file.dart';

import 'model/place.dart';
import 'residence.dart';

/// Resolves the place enclosing any path, and the ancestor chain above a
/// place.
///
/// The logged-in home and the machine root materialize as implicit places, so
/// resolution never returns "nowhere". [fs] and [home] are injected — no
/// ambient environment read — so resolution is hermetic.
final class PlaceResolver {
  PlaceResolver({required this.fs, required this.home});

  final FileSystem fs;

  /// Absolute path to the logged-in home, which materializes as an implicit
  /// place when unmarked.
  final String home;

  /// The nearest enclosing place at or above [path]. Never null: an unmarked
  /// home or the machine root materialize as implicit places.
  Place enclosing(String path) {
    var dir = fs.directory(fs.path.normalize(fs.path.absolute(path)));
    while (true) {
      if (_isMarked(dir)) return Place(this, dir);
      final atRoot = _isRoot(dir.path);
      if (_isHome(dir.path) || atRoot) {
        return Place(this, dir, isImplicit: true);
      }
      dir = dir.parent;
    }
  }

  /// The ancestor chain of [place]: places only, nearest parent → machine
  /// root, excluding [place] itself. A place at the machine root has none.
  List<Place> ancestorsOf(Place place) {
    final chain = <Place>[];
    if (_isRoot(place.root.path)) return chain;
    var dir = place.root.parent;
    while (true) {
      final atRoot = _isRoot(dir.path);
      if (_isMarked(dir)) {
        chain.add(Place(this, dir));
      } else if (_isHome(dir.path) || atRoot) {
        chain.add(Place(this, dir, isImplicit: true));
      }
      if (atRoot) break;
      dir = dir.parent;
    }
    return chain;
  }

  bool _isMarked(Directory dir) => Residence.isMarked(dir, fs);
  bool _isRoot(String path) => fs.path.dirname(path) == path;
  bool _isHome(String path) => fs.path.equals(path, home);
}
