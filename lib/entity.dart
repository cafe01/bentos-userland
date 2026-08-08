/// The WHAT primitive: the entity, its instances, the acts done to them and the
/// events those acts publish.
///
/// The class is the API. `Entity` is a peer of `Place` in idiom and in law —
/// cheap handles, anchor and referent, live reads — and the two are the
/// platform's two spatial-and-material primitives, joined by the pin and by
/// nothing else.
library;

export 'src/entity/action.dart';
export 'src/entity/entity.dart' hide gitDirOf;
export 'src/entity/entity_runner.dart';
export 'src/entity/event.dart';
export 'src/entity/installation_life.dart';
export 'src/git/git.dart';
export 'src/git/git_ambient.dart';
export 'src/entity/instance.dart';
export 'src/entity/manifest.dart';
export 'src/entity/materialization.dart';
// The transaction triple is on the surface because `emit` takes it: the
// publisher that calls it is another process holding nothing but Git's own
// stdin, so the type it parses that line into cannot be private.
export 'src/entity/transaction.dart';
export 'src/git/model/actor.dart';
export 'src/git/model/commit.dart';
export 'src/git/model/remote.dart';
export 'src/entity/workspace.dart';
