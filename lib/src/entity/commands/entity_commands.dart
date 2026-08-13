import 'package:path/path.dart' as p;

import '../entity.dart';
import '../entity_runner.dart';
import '../installation_life.dart';
import '../event.dart';
import '../manifest.dart';
import 'entity_command.dart';

/// `entity create <name>` — author one here. It has no origin and nothing to
/// fetch from; that is what separates it from [InstallCommand].
final class CreateCommand extends EntityCommand {
  CreateCommand(super.cli) {
    takesActor();
  }

  @override
  String get name => 'create';

  @override
  String get description => 'Author an entity here — no origin.';

  @override
  Future<void> run() async {
    final named = positional('name');
    // Authoring is an act with an author, and the genesis commit carries it.
    final actor = statedActor();
    final entity =
        cli.entityNamed(named, place: placeOption).create(actor: actor);
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
      // A reaction the manifest declares and this installer cannot read is said
      // out loud, here, while the person who installed it is still standing at
      // the terminal — the alternative is a declaration that silently never
      // fires, which is the failure this whole reading exists to end.
      warn: (complaint) => cli.err.writeln('entity install: $complaint'),
    );
    cli.out.writeln(entity.name);
  }
}

/// `entity refit <name>` — make an installation's **apparatus** current: the
/// shim rewritten from the running coreutil, the class tree re-staged at the
/// genesis already held.
///
/// **Local, and that word is the whole disambiguation from [UpgradeCommand]**,
/// which is why it stands in the description where a reader choosing between
/// the two already is. Nothing here reaches a remote, and none need be
/// declared.
///
/// It takes no `--dry-run`. The flag is `upgrade`'s alone, and refusing it here
/// as usage is the point: this verb moves nothing a reader would want to
/// preview, and quietly accepting a flag it ignores would teach the opposite.
final class RefitCommand extends EntityCommand {
  RefitCommand(super.cli);

  @override
  String get name => 'refit';

  @override
  String get description =>
      'Rewrite the shim and re-stage the class — local, no network.';

  @override
  Future<void> run() async {
    final named = positional('name');
    final report = cli.entityNamed(named, place: placeOption).refit();
    cli.out.writeln('shim\t${report.shim}');
    if (report.stagedAt != null) {
      cli.out.writeln('staged\t${report.stagedAt!.short}');
    }
  }
}

/// `entity upgrade <name> [--dry-run]` — bring an installation's **content**
/// forward from the remote it already declares, and then refit.
///
/// It takes no source. Pointing an installation at a different origin is a
/// re-founding and wears `install`'s risk, not this verb's.
///
/// **Where the line did not move, it says so and names `refit`** — a reader who
/// came here for the local half must leave knowing which verb does it without a
/// network, rather than inferring that from a silent zero.
final class UpgradeCommand extends EntityCommand {
  UpgradeCommand(super.cli) {
    argParser.addFlag(
      'dry-run',
      negatable: false,
      help: 'Report what a real run would, and perform nothing.',
    );
  }

  @override
  String get name => 'upgrade';

  @override
  String get description =>
      'Fetch the entity\'s line and advance it — then refit.';

  @override
  Future<void> run() async {
    final named = positional('name');
    final dryRun = argResults!['dry-run'] as bool;
    final report =
        await cli.entityNamed(named, place: placeOption).upgrade(dryRun: dryRun);

    if (dryRun) cli.out.writeln('dry-run\tnothing was performed');
    if (report.advanced) {
      // The transition, both halves of it: a sha reached with no sha left is
      // half a sentence, and a reader cannot tell it from a fresh install.
      cli.out.writeln('genesis\t${report.from?.short ?? '-'}\t${report.to.short}');
    } else {
      cli.out.writeln(
        'genesis\t${report.to.short}\tthe line did not move — '
        'refit does the local half, without a network',
      );
    }
    cli.out.writeln('armed\t${report.armed.length}');
    if (report.refit != null) cli.out.writeln('shim\t${report.refit!.shim}');
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

    final Manifest declared;
    try {
      cli.out.writeln('genesis\t${entity.genesis.sha}');
      declared = entity.manifest;
    } on Object {
      cli.err.writeln('entity info: ${entity.name} declares no manifest');
      return;
    }

    cli.out.writeln('type\t${declared.type}');
    for (final key in declared.fields.keys) {
      if (key == 'name' || key == 'type' || key == 'actions') continue;
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

/// `entity fetch <coord> <remote>` — bring a line down, **the mirror of
/// [PublishCommand]**: push moves the ref over there under the hook over there,
/// fetch moves the ref here under the hook here. The same compare-and-swap, so
/// an act received is validated, refused and reacted to exactly as one taken
/// locally.
///
/// **The remote is a declared name, never a raw URL.** The symmetry with
/// `publish` is of nature and not of signature: declaring a remote *founds a
/// relation*, which is what `remotes` exists to report, so a fetch that took a
/// URL would found one sideways and in silence, and `remotes` would begin
/// lying about who this entity speaks with. `publish` declares because
/// publishing is the founding act; `fetch` finds the relation already founded.
///
/// An undeclared name is therefore **not found** and not a refusal: refusal is
/// the answer to concurrent agency — the line diverged — and a caller retries
/// on it. Nothing about a name nobody declared is worth retrying.
final class FetchCommand extends EntityCommand {
  FetchCommand(super.cli);

  @override
  String get name => 'fetch';

  @override
  String get description => 'Bring an instance\'s line down from a remote.';

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.length < 2) usageException('fetch: <coord> <remote> are required');
    final coord = coordinate();
    final entity = cli.entityNamed(coord.entity, place: placeOption);
    final named = rest[1];
    if (!entity.remotes.any((remote) => remote.name == named)) {
      cli.err.writeln(
        'entity fetch: ${coord.entity} declares no remote $named',
      );
      cli.exitCode = EntityRunner.notFoundCode;
      return;
    }
    cli.report(await entity.instance(coord.instance).fetch(named));
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
