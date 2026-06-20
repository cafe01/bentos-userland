import 'dart:io';

import '_drivers.dart';
import 'package:args/args.dart';
import 'package:bentos_userland/bentos_userland.dart';
import 'package:bentos_userland/boot.dart';
import 'package:bentos_userland/chat.dart';
import 'package:bentos_userland/tx.dart';
import 'package:chat/chat.dart';

const _usage = '''
Usage: chat [options] <prompt>

One turn against an entity's ambient tx session — input, the model (and its
tools) in the middle, the reply at the tail, then exit. There is no REPL inside
chat; the shell is the REPL. Run chat again to continue — continuity lives in
the tx log, not in memory.

Options:
  -a, --agent <name>     The being to talk to (default: \$BENTOS_AGENT).
  -d, --device <path>    LLM device path or alias (default: openai/gpt-4o-mini).
  -s, --system <text>    System prompt. Repeatable.
  -t, --tools <dir>      Directory of tool executables + *.json definitions.
  -v, --verbose          Print Complete metadata (model · stop · usage) to stderr.
  -h, --help             Show usage.

entity = --agent <name> ?? \$BENTOS_AGENT. State at <place>/.tx/<entity>/.''';

Future<int> main(List<String> args) async {
  registerBundledLlmDrivers();

  final parser = ArgParser()
    ..addOption('agent', abbr: 'a')
    ..addOption('device', abbr: 'd')
    ..addMultiOption('system', abbr: 's')
    ..addOption('tools', abbr: 't')
    ..addFlag('verbose', abbr: 'v', negatable: false)
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults parsed;
  try {
    parsed = parser.parse(args);
  } on ArgParserException catch (e) {
    stderr.writeln('chat: ${e.message}');
    stderr.writeln(_usage);
    return 1;
  }

  if (parsed['help'] as bool) {
    stdout.writeln(_usage);
    return 0;
  }

  final positional = parsed.rest;
  if (positional.isEmpty) {
    // The bare prompt-box / interactive loop is D3b — not this deliverable.
    stderr.writeln('chat: a prompt is required (interactive mode is not yet built).');
    stderr.writeln(_usage);
    return 1;
  }

  final systemSegments = parsed['system'] as List<String>;
  final systemMessages = systemSegments.isEmpty
      ? const <ChatMessage>[]
      : [ChatMessage.systemText(systemSegments.join('\n'))];

  // Resolve the being and open its ambient session (scope=main, thread=main).
  // On a fresh session the system message is recorded so it lands in the log —
  // a native turn carries its system message.
  final ChatSession session;
  try {
    final entity = resolveEntity(
      agentFlag: parsed['agent'] as String?,
      environment: Platform.environment,
    );
    session = await ChatSession.open(
      entity,
      Directory.current,
      systemMessages: systemMessages,
    );
  } on TxResolveError catch (e) {
    stderr.writeln(e);
    return 1;
  } on TxGitError catch (e) {
    stderr.writeln(e);
    return 2;
  }

  // Open the device (capability behind /dev/llm/*; chat holds no key).
  final devicePath = _resolveDevicePath(parsed['device'] as String?);
  final BentosChatDevice device;
  try {
    device = BentosChatDevice(bootLlmDevice(devicePath), devicePath);
  } on LlmBootException catch (e) {
    stderr.writeln('chat: $e');
    return 3;
  }

  final toolsDir = parsed['tools'] as String?;
  final tools = [...builtinTools(), if (toolsDir != null) ...loadTools(toolsDir)];
  final config = ChatIOConfig(functions: tools.isEmpty ? null : tools);

  // The seam: read context from tx (system message included), run the turn,
  // append each mutation, then seal the turn with one commit.
  // Growable copy — history() may return an unmodifiable empty list.
  final conversation = [...session.history()];
  final userMsg = ChatMessage.userText(positional.join(' '));
  // Write-ahead: the input lands on disk BEFORE inference — a crash never loses
  // it. The git commit at the turn boundary seals the whole batch.
  await session.record(userMsg);
  conversation.add(userMsg);

  final turn = Turn(
    device: device,
    config: config,
    toolsDir: toolsDir,
    verbose: parsed['verbose'] as bool,
    persist: session.record,
  );

  try {
    await turn.run(conversation);
    await session.commitTurn();
    return 0;
  } on BentosException catch (e) {
    stderr.writeln('chat: $e');
    return 1;
  }
}

/// --device flag → BENTOS_LLM_DEVICE env → default; bare aliases get the
/// /dev/llm/ prefix.
String _resolveDevicePath(String? flag) {
  final explicit = (flag != null && flag.isNotEmpty)
      ? flag
      : Platform.environment['BENTOS_LLM_DEVICE'];
  if (explicit != null && explicit.isNotEmpty) {
    return explicit.startsWith('/') ? explicit : '/dev/llm/$explicit';
  }
  return '/dev/llm/openai/gpt-4o-mini';
}
