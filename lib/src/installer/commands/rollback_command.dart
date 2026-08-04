import 'package:args/command_runner.dart';

import '../bentos_runner.dart';

/// `bentos rollback` — put the previous version back.
///
/// Installing is fetch, verify, move a link; rollback is moving the link back,
/// and nothing is fetched or deleted to do it.
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
    final store = bentos.store;
    final restored = store.rollback(stream);
    if (restored == null) {
      bentos.err.writeln('bentos: "$stream" has no previous version to roll back to');
      bentos.exitCode = 1;
      return;
    }
    store.link(stream, store.namesIn(stream, restored));
    bentos.out.writeln('$stream  →  $restored');
  }
}
