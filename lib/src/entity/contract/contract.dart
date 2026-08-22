/// The entity's contract — compiling abstract Dart, one file per component,
/// every member declared exactly once on the component that owns it.
///
/// Superseded as a specification by `bentos-platform/place-and-entity` and
/// `bentos-platform/substrate/git` in the brain: what survives here is only
/// what git does not already do (the arming table, `run`, the manifest as
/// policy data, and the substrate mapping) plus the flow operations. The
/// requirements and design specifications that used to govern this file
/// predate that measurement and are superseded where they disagree with it.
library;

export 'event.dart';
export 'flow.dart';
export 'function.dart';
export 'instance.dart';
export 'manifest.dart';
export 'spine.dart';
export 'substrate.dart';
