import 'package:args/command_runner.dart';

import '../bentos_runner.dart';

/// `bentos update` — install the latest release of a stream.
///
/// It does itself first: an updater that cannot replace itself has to be
/// replaced by hand exactly when it is most broken.
final class UpdateCommand extends Command<void> {
  UpdateCommand(this.bentos) {
    argParser.addOption(
      'stream',
      abbr: 's',
      help: 'the producing repo to update from',
      defaultsTo: BentosRunner.defaultStream,
    );
  }

  final BentosRunner bentos;

  @override
  String get name => 'update';

  @override
  String get description => 'Update to the latest release (self first).';

  @override
  Future<void> run() async {
    bentos.adoptLegacyLayout();
    final stream = argResults!['stream'] as String;
    final installer = bentos.installer;
    final source = installer.sourceFor(stream);
    final manifest = await source.manifest();

    if (manifest.names.contains(BentosRunner.selfName)) {
      bentos.report(await installer.install(
        stream: stream,
        names: const [BentosRunner.selfName],
        from: source,
      ));
    }
    bentos.report(await installer.install(stream: stream, from: source));
  }
}

/// `bentos self-update` — the updater alone, for when the rest of the userland
/// should not move.
final class SelfUpdateCommand extends Command<void> {
  SelfUpdateCommand(this.bentos) {
    argParser.addOption(
      'stream',
      abbr: 's',
      defaultsTo: BentosRunner.defaultStream,
    );
  }

  final BentosRunner bentos;

  @override
  String get name => 'self-update';

  @override
  String get description => 'Update the installer itself.';

  @override
  Future<void> run() async {
    bentos.report(await bentos.installer.install(
      stream: argResults!['stream'] as String,
      names: const [BentosRunner.selfName],
    ));
  }
}
