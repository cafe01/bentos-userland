/// The place's contract — compiling abstract Dart, one file per component,
/// every member declared exactly once on the component that owns it. The
/// bodies throw [UnimplementedError] until the build lands: the design suite
/// under `test/place/design/` reds through them, never through skips.
///
/// See `bentos-platform/userland/place/design-specification` in the brain.
library;

export 'arrangement.dart';
export 'constellation.dart';
export 'copy_gate.dart';
export 'face.dart';
export 'place.dart';
export 'presence.dart';
export 'record.dart';
export 'resolver.dart';
export 'survey.dart';
