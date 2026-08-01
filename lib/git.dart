/// The Git port — the substrate both primitives stand on.
///
/// It is not the entity's ontology and never was: `Entity` and `Place` are two
/// sisters that both speak Git, and this is the one storey where Git's own
/// dialect — refs, trees, objects, worktrees, gitlinks — is legal. Above it the
/// names belong to whichever primitive is speaking.
///
/// The port exists because `IOOverrides` does not reach subprocesses. It is
/// injected as a zone-scoped ambient, never as a constructor argument, so that
/// handles on both sides stay bare.
library;

export 'src/git/git.dart';
export 'src/git/git_ambient.dart';
export 'src/git/model/actor.dart';
export 'src/git/model/commit.dart';
export 'src/git/model/remote.dart';
