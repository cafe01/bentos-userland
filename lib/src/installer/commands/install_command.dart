import 'package:args/command_runner.dart';

import '../bentos_runner.dart';

/// `bentos install [name ...]` — fetch from the stream, verify, link.
/// With no names, the whole release.
final class InstallCommand extends Command<void> {
  InstallCommand(this.bentos) {
    argParser.addOption(
      'stream',
      abbr: 's',
      help: 'the producing repo to install from',
      defaultsTo: BentosRunner.defaultStream,
    );
  }

  final BentosRunner bentos;

  @override
  String get name => 'install';

  @override
  String get description => 'Install executables from a release stream.';

  @override
  String get invocation => 'bentos install [name ...]';

  @override
  Future<void> run() async {
    final stream = argResults!['stream'] as String;
    final report = await bentos.installer.install(
      stream: stream,
      names: argResults!.rest,
    );
    bentos.report(report);
  }
}
