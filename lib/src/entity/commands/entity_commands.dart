import 'entity_command.dart';

/// `entity create <name>` — author one here. It has no origin and nothing to
/// fetch from; that is what separates it from [InstallCommand].
final class CreateCommand extends EntityCommand {
  CreateCommand(super.cli);

  @override
  String get name => 'create';

  @override
  String get description => 'Author an entity here — no origin.';

  @override
  Future<void> run() => throw UnimplementedError('entity create');
}

/// `entity install <source> [--as <name>]` — the common act: a platform's
/// ordinary day is bringing in what someone else made.
///
/// **Install is the entity's verb**, even though half of it is the place's to
/// perform: clone and arm are the entity's, register and pin are the place's,
/// because the gitlink lives in the place's own tree and no tenant writes
/// there. One act, one command, and the ownership of each half is settled in
/// the gate rather than in the surface.
///
/// It does not materialize. A site that only reacts holds no worktree at all.
final class InstallCommand extends EntityCommand {
  InstallCommand(super.cli) {
    argParser.addOption('as', help: 'Install under a different name.');
  }

  @override
  String get name => 'install';

  @override
  String get description => 'Clone an entity into this place, register it, arm it.';

  @override
  Future<void> run() => throw UnimplementedError('entity install');
}

/// `entity which <name>` — which installation the name resolves to, from here.
/// The walk up the tree of places, made visible: nearest wins, and an
/// installation lower down shadows one above.
final class WhichCommand extends EntityCommand {
  WhichCommand(super.cli);

  @override
  String get name => 'which';

  @override
  String get description => 'Which installation this name resolves to.';

  @override
  Future<void> run() => throw UnimplementedError('entity which');
}

/// `entity info <name>` — the manifest: type, parts, actions, events.
///
/// **Reflection, never invocation.** It prints the vocabulary a type declares;
/// the events are that vocabulary crossed with the three phases, which is why
/// nothing declares events anywhere.
final class InfoCommand extends EntityCommand {
  InfoCommand(super.cli);

  @override
  String get name => 'info';

  @override
  String get description => 'The manifest: type, parts, actions, events.';

  @override
  Future<void> run() => throw UnimplementedError('entity info');
}

/// `entity publish <name> <remote>` — give it an origin.
///
/// The push moves bytes. That the remote is now authoritative is a
/// declaration, never a consequence of the mechanism.
final class PublishCommand extends EntityCommand {
  PublishCommand(super.cli);

  @override
  String get name => 'publish';

  @override
  String get description => 'Give an entity an origin and push to it.';

  @override
  Future<void> run() => throw UnimplementedError('entity publish');
}

/// `entity remotes <name>` — where bytes may travel from here.
final class RemotesCommand extends EntityCommand {
  RemotesCommand(super.cli);

  @override
  String get name => 'remotes';

  @override
  String get description => 'The declared remotes.';

  @override
  Future<void> run() => throw UnimplementedError('entity remotes');
}
