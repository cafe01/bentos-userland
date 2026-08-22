/// `instance` — the object everyone touches.
///
/// The existence half that used to live here — identity, title, birth, reads
/// at a point and as of an instant — is cut. `here` is `rev-parse`,
/// `history()` is `log`, `read()` is `show`, `atSources` is remote-tracking
/// refs, and `born`/`ForkedFrom` is an ordinary commit: git already does all
/// of it, and `lib/src/entity/instance.dart` already ships it under its own
/// names. What is left is the one slice git does not do.
///
/// One type, one component: [Instance] is [InstanceFunctions] and nothing
/// else, until a live standing verb is designed to sit beside it.
library;

import 'function.dart';

/// The whole of an instance, taken together.
abstract interface class Instance implements InstanceFunctions {}
