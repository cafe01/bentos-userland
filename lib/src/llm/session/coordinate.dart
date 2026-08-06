/// Where a conversation is, and how a verb finds it when nobody typed one.
///
/// The coordinate is `<entity>:<instance>`; the **vantage** is the place it
/// resolves from, and the two are different facts. The primitive owns both — the
/// grammar and the ambient variable — so nothing here spells the name of an
/// environment variable. A face that fixed that name would be a face deciding a
/// convention that belongs one floor down.
library;

/// The entity half is spellable and never assumed: the face is a face of any
/// body that fuses the session ontology.
final class Coordinate {
  const Coordinate(this.entity, this.instance);

  final String entity;
  final String instance;
}

/// The place a coordinate resolves from. Null is the vantage the caller stands
/// in, which is what the primitive already does on its own.
final class Vantage {
  const Vantage(this.place);
  const Vantage.here() : place = null;

  final String? place;
}

/// Which step of the precedence answered. A person asking *where am I* is asking
/// this as much as they are asking for the coordinate.
enum CoordinateOrigin {
  /// Typed on the line. Always wins, and is what keeps every verb scriptable
  /// with no environment at all.
  argument,

  /// The ontology's ambient variable, as the primitive spells it.
  ambient,

  /// Derived from the place: one instance of that ontology here is the one.
  place,
}

/// A resolved coordinate, with the step it came from.
final class CoordinateResolution {
  const CoordinateResolution(this.coordinate, this.origin);

  final Coordinate coordinate;
  final CoordinateOrigin origin;
}

/// Raised when resolution cannot answer. Both shapes are informative rather than
/// arbitrary: nothing is chosen alphabetically and nothing is stored to make the
/// question go away.
final class CoordinateAmbiguous implements Exception {
  const CoordinateAmbiguous(this.candidates);

  /// Every instance of the ontology standing in this place.
  final List<Coordinate> candidates;
}

final class CoordinateAbsent implements Exception {
  const CoordinateAbsent();
}

final class CoordinateMalformed implements Exception {
  const CoordinateMalformed(this.spelled);
  final String spelled;
}

/// The one place the face asks *which conversation*.
///
/// **The face owns no step of this.** The grammar and the ambient variable are
/// the primitive's, and this port is where that dependency is declared: until
/// `entity` answers it, the implementation behind this interface is the red the
/// gate names, and the day it lands nothing above this line changes.
abstract interface class CoordinateSource {
  /// [spelled] is what the caller typed, or null when they typed nothing.
  ///
  /// Throws [CoordinateMalformed] on a spelling that is not a coordinate,
  /// [CoordinateAmbiguous] when the place holds more than one, and
  /// [CoordinateAbsent] when no step answers.
  Future<CoordinateResolution> resolve(String? spelled, {Vantage vantage});

  /// The shell line that puts [coordinate] in the ambient, for `use` to print.
  /// A child process does not write its parent's environment; the honest form is
  /// old, and the primitive is what knows the variable's name.
  Future<String> exportLine(Coordinate coordinate);
}
