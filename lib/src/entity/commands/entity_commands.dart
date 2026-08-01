import 'package:path/path.dart' as p;

import '../entity.dart';
import '../event.dart';
import '../manifest.dart';
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
  Future<void> run() async {
    final named = positional('name');
    final entity = cli.entityNamed(named, place: placeOption).create();
    cli.out.writeln(entity.genesis.sha);
  }
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
  Future<void> run() async {
    final source = positional('source');
    final entity = await Entity.install(
      cli.locate(source),
      at: cli.vantage(placeOption),
      as: argResults!['as'] as String?,
    );
    cli.out.writeln(entity.name);
  }
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
  Future<void> run() async {
    final named = positional('name');
    cli.out.writeln(cli.installedAt(named, place: placeOption).path);
  }
}

/// `entity info <name>` — the manifest: type, parts, actions, events.
///
/// **Reflection, never invocation.** It prints the vocabulary a type declares;
/// the events are that vocabulary crossed with the three phases, which is why
/// nothing declares events anywhere.
///
/// An entity that declares nothing is not a fault. `create` leaves a genesis
/// with no manifest in it, and the honest report of that is the name, the
/// genesis, and a word on stderr — never a non-zero exit, because the thing
/// exists and is answering.
final class InfoCommand extends EntityCommand {
  InfoCommand(super.cli);

  @override
  String get name => 'info';

  @override
  String get description => 'The manifest: type, parts, actions, events.';

  @override
  Future<void> run() async {
    final named = positional('name');
    final entity = cli.entityNamed(named, place: placeOption);
    cli.out.writeln('name\t${entity.name}');
    cli.out.writeln('genesis\t${entity.genesis.sha}');

    final Manifest declared;
    try {
      declared = entity.manifest;
    } on Object {
      cli.err.writeln('entity info: ${entity.name} declares no manifest');
      return;
    }

    cli.out.writeln('type\t${declared.type}');
    for (final key in declared.fields.keys) {
      if (key == 'type' || key == 'actions') continue;
      cli.out.writeln('$key\t${declared.fields[key]}');
    }
    for (final action in declared.actions) {
      cli.out.writeln('action\t$action');
    }
    // The event vocabulary is derived and never declared: the actions crossed
    // with the three phases, which is the whole of what an entity publishes.
    for (final action in declared.actions) {
      for (final phase in EventPhase.values) {
        cli.out.writeln('event\t$action.${phase.suffix}');
      }
    }
  }
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
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.length < 2) usageException('publish: <name> <remote> are required');
    await cli.entityNamed(rest[0], place: placeOption).publish(cli.locate(rest[1]));
  }
}

/// `entity remotes <name>` — where bytes may travel from here.
final class RemotesCommand extends EntityCommand {
  RemotesCommand(super.cli);

  @override
  String get name => 'remotes';

  @override
  String get description => 'The declared remotes.';

  @override
  Future<void> run() async {
    final named = positional('name');
    for (final remote in cli.entityNamed(named, place: placeOption).remotes) {
      cli.out.writeln('${remote.name}\t${remote.url}');
    }
  }
}

/// The path grammar the two verbs that take a *source* share: a local source is
/// resolved against the injected working directory, and anything with a scheme
/// or an ssh shorthand is left exactly as written.
bool isLocalSource(String source) =>
    !source.contains('://') && !RegExp(r'^[^/]+@').hasMatch(source);

/// A local source made absolute against [from]; anything else, verbatim.
String locateSource(String source, {required String from}) =>
    isLocalSource(source) && !p.isAbsolute(source)
        ? p.normalize(p.join(from, source))
        : source;
