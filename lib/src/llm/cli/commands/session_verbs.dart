/// The person's verbs: the transactions a hand at the shell writes onto a
/// session. Each is one commit and then silence — the face never calls a device,
/// and what its commit wakes is not its business.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:chat_inference/chat_inference.dart';

import '../../../../llm_session.dart';
import '../../device.dart';
import '../../function_file.dart';
import '../../llm_config.dart';
import 'session_command.dart';

/// The knobs of a channel, as flags. They are the same at `open` and at
/// `configure`; what differs is that `configure` keeps what was not passed.
void addChannelOptions(ArgParser parser) {
  parser
    ..addOption(
      'device',
      abbr: 'd',
      help: 'Device path /dev/llm/<vendor>/<model> — '
          '/dev/llm/fixture/weather walks without a credential.',
    )
    ..addOption('max-tokens', abbr: 't', help: 'Cap the generated length.', valueHelp: 'n')
    ..addOption('temperature', help: 'Sampling temperature.', valueHelp: '0.0–1.0')
    ..addOption(
      'reasoning-budget',
      help: 'Thinking budget in tokens (0/absent = off).',
      valueHelp: 'n',
    )
    ..addMultiOption(
      'function',
      help: 'Declare a callable function from a JSON file '
          '({"name","description","inputSchema"}). Repeatable.',
      valueHelp: 'file.json',
    )
    ..addOption(
      'function-choice',
      help: 'auto (default with functions) · none · a function name.',
      valueHelp: 'auto|none|name',
    );
}

/// The channel the flags describe. [from] is the channel already in the entity,
/// so an unpassed knob keeps the value the session was tuned to.
Channel channelFrom(ArgResults args, String usage, {Channel? from}) {
  final device = args.wasParsed('device') || from == null
      ? resolveDevicePath(
          args['device'] as String?,
          environment: Platform.environment,
          config: LlmConfig.load(),
        )
      : from.deviceId;

  final paths = args['function'] as List<String>;
  final functions = paths.isEmpty
      ? null
      : [for (final path in paths) _loadFunction(path, usage)];
  final choice = _parseChoice(args['function-choice'] as String?) ??
      (functions == null ? null : const AutoChoice());

  final base = from?.config ?? const ChatIOConfig();
  return Channel(
    deviceId: device,
    config: base.copyWith(
      maxTokens: _int(args, 'max-tokens', usage),
      temperature: _double(args, 'temperature', usage),
      reasoningBudget: _int(args, 'reasoning-budget', usage),
      functions: functions,
      functionChoice: choice,
    ),
  );
}

class SessionOpenCommand extends SessionCommandBase {
  SessionOpenCommand({super.out, super.err}) : super(withRef: false, withSeat: true) {
    addChannelOptions(argParser);
    argParser
      ..addMultiOption(
        'system',
        abbr: 's',
        help: 'The system prompt. Repeatable — segments are joined in order. '
            'It is the leading message, not a knob.',
        valueHelp: 'text',
      )
      ..addOption('title', help: "The session's name.", defaultsTo: 'New session')
      ..addFlag(
        'arm',
        defaultsTo: true,
        help: 'Arm the assistant runner on every transaction. --no-arm opens a '
            'session nobody answers — one whose transactions travel to wherever '
            'the assistant runs.',
      )
      ..addOption(
        'runner',
        help: 'The command line armed as the assistant body.',
        defaultsTo: defaultRunnerCommand,
      );
  }

  @override
  String get name => 'open';

  @override
  String get description =>
      'Create a session: the repository, the channel, the system prompt, the arming.';

  @override
  String get invocation =>
      'llm session open <session.llm> [-d <device>] [-s <system>] [--title <t>]';

  @override
  Future<int> act() async {
    final segments = argResults!['system'] as List<String>;
    final session = await Session.open(
      entityDir,
      channel: channelFrom(argResults!, usage),
      author: seat,
      title: argResults!['title'] as String,
      systemPrompt: segments.isEmpty ? null : segments.join('\n'),
      runnerCommand:
          (argResults!['arm'] as bool) ? argResults!['runner'] as String : '',
    );
    final state = await session.state;
    out.writeln('${entityDir.path} · ${state.channel.deviceId} · ${await session.debt}');
    return 0;
  }
}

class SessionSayCommand extends SessionCommandBase {
  SessionSayCommand({super.out, super.err}) : super(withSeat: true);

  @override
  String get name => 'say';

  @override
  String get description =>
      'Speak as the user. The origin of everything: only the user starts a turn.';

  @override
  String get invocation => 'llm session say <session.llm> <text>   (or pipe the text)';

  @override
  Future<int> act() async {
    final text = await turnText();
    final tx = await session.say(ChatMessage.userText(text), author: seat);
    out.writeln(tx.message);
    return 0;
  }
}

class SessionReturnCommand extends SessionCommandBase {
  SessionReturnCommand({super.out, super.err}) : super(withSeat: true) {
    argParser
      ..addOption('call', help: 'The call id being answered.', valueHelp: 'id')
      ..addFlag(
        'error',
        negatable: false,
        help: 'The call failed, and this is what it failed with.',
      );
  }

  @override
  String get name => 'return';

  @override
  String get description =>
      "Answer one function call — the executor's seat, occupied by hand.";

  @override
  String get invocation =>
      'llm session return <session.llm> --call <id> <result>   (or pipe the result)';

  @override
  Future<int> act() async {
    final callId = argResults!['call'] as String?;
    if (callId == null || callId.isEmpty) {
      throw UsageException('--call <id> is required: a result answers one call', usage);
    }
    final text = await turnText();
    final tx = await session.returnResult(
      callId: callId,
      content: [TextContent(text)],
      author: seat,
      isError: argResults!['error'] as bool,
    );
    out.writeln(tx.message);
    return 0;
  }
}

class SessionConfigureCommand extends SessionCommandBase {
  SessionConfigureCommand({super.out, super.err}) : super(withSeat: true) {
    addChannelOptions(argParser);
  }

  @override
  String get name => 'configure';

  @override
  String get description =>
      'Retune the channel. Applies to the next turn and rewrites no past one — '
      'every turn keeps the marker it ran under.';

  @override
  String get invocation => 'llm session configure <session.llm> [-d <device>] [knobs]';

  @override
  Future<int> act() async {
    final current = (await session.state).channel;
    final tx = await session.configure(
      channelFrom(argResults!, usage, from: current),
      author: seat,
    );
    out.writeln(tx.message);
    return 0;
  }
}

class SessionRenameCommand extends SessionCommandBase {
  SessionRenameCommand({super.out, super.err}) : super(withSeat: true);

  @override
  String get name => 'rename';

  @override
  String get description => "Move the session's title — entity state, and so an act.";

  @override
  String get invocation => 'llm session rename <session.llm> <title>';

  @override
  Future<int> act() async {
    final rest = argResults!.rest;
    if (rest.length < 2) throw UsageException('a title is required', usage);
    final tx = await session.rename(rest.skip(1).join(' '), author: seat);
    out.writeln(tx.message);
    return 0;
  }
}

class SessionForkCommand extends SessionCommandBase {
  SessionForkCommand({super.out, super.err}) {
    argParser.addOption(
      'at',
      help: 'The transaction to branch from. Defaults to the tip.',
      valueHelp: 'commit',
    );
  }

  @override
  String get name => 'fork';

  @override
  String get description =>
      'Branch the session: an alternative continuation over the same history, '
      "which is what an entity's branches mean.";

  @override
  String get invocation => 'llm session fork <session.llm> <name> [--at <commit>]';

  @override
  Future<int> act() async {
    final rest = argResults!.rest;
    if (rest.length < 2) throw UsageException('a fork needs a name', usage);
    final at = argResults!['at'] as String? ?? await session.tip;
    if (at == null) throw UsageException('nothing to fork — the line is unborn', usage);
    final forked = await session.forkAt(at, name: rest[1]);
    out.writeln('${forked.ref} · at ${at.substring(0, 7)}');
    return 0;
  }
}

FunctionDefinition _loadFunction(String path, String usage) {
  try {
    return loadFunctionDefinitionFromFile(path);
  } on ArgumentError catch (e) {
    throw UsageException('--function: ${e.message}', usage);
  } on FormatException catch (e) {
    throw UsageException('--function: malformed JSON in $path — $e', usage);
  }
}

FunctionChoice? _parseChoice(String? value) => switch (value) {
      null => null,
      'auto' => const AutoChoice(),
      'none' => const NoneChoice(),
      _ => NamedChoice(value),
    };

int? _int(ArgResults args, String option, String usage) {
  final raw = args[option] as String?;
  if (raw == null) return null;
  final value = int.tryParse(raw);
  if (value == null) throw UsageException('--$option: "$raw" is not a number', usage);
  return value;
}

double? _double(ArgResults args, String option, String usage) {
  final raw = args[option] as String?;
  if (raw == null) return null;
  final value = double.tryParse(raw);
  if (value == null) throw UsageException('--$option: "$raw" is not a number', usage);
  return value;
}
