/// `chat monitor` — the screen. Reads the tree, translates, prints, exits.
///
/// A render of one time arms nothing. `-f` is what would arm, and it is not here
/// yet: the registration it needs is `notify`, which the primitive does not
/// offer. Until it does, a second window looking at the same conversation
/// refreshes by being run again.
library;

import 'dart:io';

import '../lens.dart';
import 'chat_base_command.dart';

final class MonitorCommand extends ChatBaseCommand {
  MonitorCommand() {
    argParser.addOption(
      'lens',
      abbr: 'l',
      allowed: ['conversation', 'work', 'audit'],
      defaultsTo: 'conversation',
      allowedHelp: {
        'conversation': 'you and the agent — calls collapsed, reasoning hidden',
        'work': 'the machinery — calls, arguments, results, reasoning',
        'audit': 'the acts — noun, actor, sha',
      },
    );
  }

  @override
  String get name => 'monitor';

  @override
  String get description => 'Show the conversation.';

  @override
  String get invocation => 'chat monitor';

  @override
  Future<int> run() async {
    final session = this.session;
    final lens = Lens.values.byName(argResults!['lens'] as String);

    // One screen is one point in history: the tip is taken once and everything
    // below is read there.
    final at = await session.tip();
    if (at == null) {
      stderr.writeln('chat: ${session.coord} has not been opened yet');
      return 1;
    }

    if (lens == Lens.audit) {
      stdout.write(await session.log());
      return 0;
    }

    final transcript = await session.transcript(asOf: at);
    for (final line in renderTranscript(transcript, lens)) {
      stdout.writeln(line);
    }
    stdout.writeln('-- ${await session.state(asOf: at)}');
    return 0;
  }
}
