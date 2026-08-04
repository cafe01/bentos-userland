import 'package:args/command_runner.dart';

import '../bentos_runner.dart';

/// `bentos rollback` — put the previous version back.
///
/// Installing is fetch, verify, substitute; rollback is substituting back, and
/// nothing is fetched or deleted to do it — the earlier version's artifacts
/// were never removed.
final class RollbackCommand extends Command<void> {
  RollbackCommand(this.bentos) {
    argParser.addOption(
      'stream',
      abbr: 's',
      defaultsTo: BentosRunner.defaultStream,
    );
  }

  final BentosRunner bentos;

  @override
  String get name => 'rollback';

  @override
  String get description => 'Return a stream to its previous version.';

  @override
  Future<void> run() async {
    final stream = argResults!['stream'] as String;
    final report = bentos.installer.rollback(stream);
    if (report == null) {
      bentos.err.writeln('bentos: "$stream" has no previous version to roll back to');
      bentos.exitCode = 1;
      return;
    }
    bentos.report(
      report,
      headline: '$stream ${report.version}  →  ${bentos.config.prefix}  '
          '(rolled back from ${report.replaced})',
    );
  }
}
