/// `chat new` — a conversation begins, in one line.
///
/// Opening is one act at a coordinate that is not yet born. Everything else here
/// is the arming, and the arming is on loan.
library;

import 'dart:io';

import 'package:args/command_runner.dart';

import '../session.dart';
import 'chat_base_command.dart';

final class NewCommand extends ChatBaseCommand {
  NewCommand() {
    argParser
      ..addOption(
        'as',
        help: 'The name of the conversation.\n'
            'Defaults to a timestamp.',
      )
      ..addOption(
        'entity',
        defaultsTo: Coordinate.defaultEntity,
        help: 'The body the conversation runs on — anything that fuses\n'
            '${Coordinate.defaultEntity}.',
      )
      ..addOption('device', help: 'The model device replies run against.')
      ..addOption(
        'system',
        help: 'The constitution: a path to read, or the text itself.\n'
            'A real constitution does not fit in argv, so a path that\n'
            'exists is read.',
      )
      ..addOption(
        'tools',
        help: 'A directory of functions to plug: <name> executable beside\n'
            '<name>.json declaring it.',
      );
  }

  @override
  String get name => 'new';

  @override
  String get description => 'Open a conversation.';

  @override
  String get invocation => 'chat new [--as <name>]';

  @override
  Future<int> run() async {
    final instance = argResults!['as'] as String? ?? _stamp();
    final session = Session(Coordinate(
      argResults!['entity'] as String,
      instance,
      place: placeFrom(globalResults),
    ));

    if (await session.tip() != null) {
      stderr.writeln('chat new: ${session.coord} already exists');
      return 1;
    }

    final device = argResults!['device'] as String?;
    final tools = argResults!['tools'] as String?;
    if (tools != null && !Directory(tools).existsSync()) {
      throw UsageException('chat new: no such directory: $tools', usage);
    }

    final opened = await session.run('user.open', [
      if (device != null) ...['--device', device],
      if (argResults!['system'] != null)
        ...['--system', _constitution(argResults!['system'] as String)],
      if (tools != null) ...['--functions', tools],
    ]);
    if (opened != 0) return opened;

    final armed = await _armTheCircuit(session);
    if (armed != 0) return armed;

    stdout.writeln(session.coord.instance);
    stderr.writeln('chat: talk to it with  chat -s ${session.coord} ');
    return 0;
  }

  /// A constitution is text, and text this long lives in a file. A value that
  /// names an existing file is read; anything else is the text itself.
  String _constitution(String value) {
    final file = File(value);
    return file.existsSync() ? file.readAsStringSync() : value;
  }

  /// ---------------------------------------------------------------------
  /// ON LOAN — delete this whole function when `install` reads the manifest.
  ///
  /// The entity already declares these three landings in its `on:` table, and
  /// `install` is what will write them. Until it does, a session that nobody
  /// armed is a session that never answers, so the client does it — and only
  /// for the conversation it just opened, never for `*`, because a listener
  /// cannot be told which instance woke it and one armed across all of them
  /// runs every other session's bodies.
  ///
  /// When the other front lands: remove this, remove the call above, and
  /// nothing else in the client changes.
  /// ---------------------------------------------------------------------
  Future<int> _armTheCircuit(Session session) async {
    const circuit = <(String, String)>[
      ('prompt.landed', 'assistant.reply'),
      ('function-result.landed', 'assistant.reply'),
      ('reply.landed', 'executor.run'),
    ];
    for (final (event, function) in circuit) {
      final rc = await session.arm(event, function);
      if (rc != 0) {
        stderr.writeln('chat new: could not arm $event → $function');
        return rc;
      }
    }
    return 0;
  }

  static String _stamp() {
    final now = DateTime.now().toUtc().toIso8601String();
    return now.substring(0, 19).replaceAll(RegExp(r'[-:]'), '').replaceFirst(
          'T',
          '-',
        );
  }
}
