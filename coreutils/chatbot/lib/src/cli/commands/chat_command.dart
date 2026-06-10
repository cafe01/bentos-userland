/// `chatbot` default command — single-shot and interactive REPL.
///
/// When a positional argument is supplied (`chatbot "prompt"`): one turn, stream
/// the reply, exit (no session persisted). When invoked bare (`chatbot`): REPL
/// loop — each turn is appended to a session log on disk, `/exit` or Ctrl-D
/// seals the session.
library;

import 'dart:convert';
import 'dart:io';

import 'package:bentos_userland/bentos_userland.dart';
import 'package:bentos_userland/boot.dart';
import 'package:bentos_userland/chat.dart';

import '../../session/session_store.dart';
import 'chatbot_base_command.dart';

class ChatCommand extends ChatbotBaseCommand {
  static const _maxToolIter = 20;

  ChatCommand() {
    argParser
      ..addOption(
        'name',
        abbr: 'n',
        help: 'Human name for this session (instead of an auto-generated ID).',
        valueHelp: 'name',
      )
      ..addOption(
        'tools',
        abbr: 't',
        help:
            'Directory of tool executables and *.json FunctionDefinition files.',
        valueHelp: 'dir',
      );
  }

  @override
  String get name => 'chat';

  @override
  String get description =>
      'Start or continue a conversation (default command).';

  @override
  String get invocation =>
      'chatbot [-d <device>] [-s <system>]... [-n <name>] [-t <tools>] [-v] [<prompt>]';

  @override
  Future<int> run() async {
    final devicePath = resolveDevicePath();
    final BentosChatDevice device;
    try {
      device = BentosChatDevice(bootLlmDevice(devicePath), devicePath);
    } on LlmBootException catch (e) {
      stderr.writeln('chatbot: $e');
      return 3;
    }

    final toolsDir = argResults!['tools'] as String?;
    final tools = [
      ..._builtinTools(),
      if (toolsDir != null) ..._loadTools(toolsDir),
    ];
    final config = ChatIOConfig(functions: tools.isEmpty ? null : tools);

    final positional = argResults!.rest;
    if (positional.isNotEmpty) {
      return _singleShot(device, positional.join(' '), config, toolsDir);
    }
    return _repl(device, config, toolsDir);
  }

  Future<int> _singleShot(
    BentosChatDevice device,
    String prompt,
    ChatIOConfig config,
    String? toolsDir,
  ) async {
    final conversation = [ChatMessage.userText(prompt)];
    try {
      await _agentTurn(device, conversation, config, toolsDir);
      return 0;
    } on BentosException catch (e) {
      stderr.writeln('chatbot: $e');
      return 1;
    }
  }

  Future<int> _repl(
    BentosChatDevice device,
    ChatIOConfig config,
    String? toolsDir,
  ) async {
    final store = SessionStore.open();
    final sessionName = argResults!['name'] as String?;
    final sessionId = store.create(name: sessionName);
    final conversation = <ChatMessage>[];

    while (true) {
      stdout.write('> ');
      final line = stdin.readLineSync();
      if (line == null) {
        stdout.writeln();
        break;
      }
      final input = line.trim();
      if (input == '/exit') break;
      if (input.isEmpty) continue;

      final userMsg = ChatMessage.userText(input);
      conversation.add(userMsg);
      await store.append(sessionId, [userMsg]);

      // Mark where agent messages will begin so we can flush them to disk.
      final agentStart = conversation.length;
      try {
        await _agentTurn(device, conversation, config, toolsDir);
        await store.append(sessionId, conversation.sublist(agentStart));
      } on BentosException catch (e) {
        stderr.writeln('chatbot: $e');
        return 1;
      }
    }

    final label = sessionName ?? sessionId;
    stderr.writeln('Session $label sealed.');
    return 0;
  }

  // ---------------------------------------------------------------------------
  // Agent loop (tool dispatch)
  // ---------------------------------------------------------------------------

  /// Runs the tool-dispatch loop for one user turn.
  ///
  /// Appends every new message (assistant turns and tool results) to
  /// [conversation] as it goes. Returns the final text reply.
  Future<String> _agentTurn(
    BentosChatDevice device,
    List<ChatMessage> conversation,
    ChatIOConfig config,
    String? toolsDir,
  ) async {
    for (var iter = 0; iter < _maxToolIter; iter++) {
      final assistantMsg = await _streamTurn(device, conversation, config);
      conversation.add(assistantMsg);

      final calls =
          assistantMsg.content.whereType<FunctionCallContent>().toList();
      if (calls.isEmpty) {
        return assistantMsg.content
            .whereType<TextContent>()
            .map((c) => c.text)
            .join();
      }

      // Dispatch all function calls in this turn in parallel.
      final results = await Future.wait(
        calls.map((call) => _dispatch(call, toolsDir)),
      );
      // All results in ONE domain message — the subsystem contract.
      // The driver expands N results → N wire messages internally.
      conversation.add(ChatMessage(role: ChatRole.user, content: results));
    }

    stderr.writeln(
      'chatbot: stop-guard reached ($_maxToolIter tool iterations)',
    );
    return '';
  }

  // ---------------------------------------------------------------------------
  // Inference
  // ---------------------------------------------------------------------------

  /// Runs one inference turn, streaming text deltas to stdout.
  ///
  /// Returns the full assembled assistant [ChatMessage] (including any
  /// [FunctionCallContent] blocks the model emitted).
  Future<ChatMessage> _streamTurn(
    BentosChatDevice device,
    List<ChatMessage> messages,
    ChatIOConfig config,
  ) async {
    final wire = [...systemMessages, ...messages];
    final textBufs = <int, StringBuffer>{};
    final blockContents = <int, ChatContent>{};

    await for (final event
        in device.infer(wire, config).foldFunctionCalls()) {
      switch (event) {
        case TextStart(:final index):
          textBufs[index] = StringBuffer();
        case TextDelta(:final index, :final text):
          stdout.write(text);
          textBufs[index]?.write(text);
        case TextStop(:final index):
          final buf = textBufs.remove(index);
          if (buf != null) blockContents[index] = TextContent(buf.toString());
        case Block(:final index, :final content):
          blockContents[index] = content;
        case Complete(:final metadata):
          stdout.writeln();
          if (verbose) {
            stderr.writeln(
              '[${metadata.model} · ${metadata.stopReason} · '
              '${metadata.usage?.inputTokens}in/'
              '${metadata.usage?.outputTokens}out]',
            );
          }
        default:
          break;
      }
    }

    final content = (blockContents.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)))
        .map((e) => e.value)
        .toList();
    return ChatMessage(role: ChatRole.assistant, content: content);
  }

  // ---------------------------------------------------------------------------
  // Tool dispatch
  // ---------------------------------------------------------------------------

  /// Invokes one tool executable: args JSON on stdin → result text on stdout.
  ///
  /// Resolution order: (1) explicit toolsDir, (2) PATH (built-in coreutils).
  Future<FunctionResultContent> _dispatch(
    FunctionCallContent call,
    String? toolsDir,
  ) async {
    // Prefer a file in the explicit tools dir; fall back to PATH resolution.
    String? toolPath;
    if (toolsDir != null) {
      final candidate = '$toolsDir/${call.name}';
      if (File(candidate).existsSync()) toolPath = candidate;
    }
    // PATH fallback — covers built-in coreutils (websearch, etc.).
    toolPath ??= _resolveOnPath(call.name);

    if (toolPath == null) {
      stderr.writeln('chatbot: tool not found: ${call.name}');
      return FunctionResultContent(
        callId: call.id,
        content: [TextContent('tool not found: ${call.name}')],
        isError: true,
      );
    }

    // Built-in coreutils speak CLI args; tools in an explicit dir speak
    // JSON-on-stdin (the D3a adapter protocol). Distinguish by whether a
    // toolsDir was the source of this path.
    final isBuiltin = toolsDir == null ||
        !File('$toolsDir/${call.name}').existsSync();

    final Process process;
    if (isBuiltin) {
      // Translate FunctionCall arguments → CLI flags for built-in coreutils.
      final cliArgs = _builtinArgs(call.name, call.arguments);
      process = await Process.start(toolPath, cliArgs);
    } else {
      process = await Process.start(toolPath, []);
      process.stdin.write(jsonEncode(call.arguments));
      await process.stdin.flush();
      await process.stdin.close();
    }

    final output = await process.stdout.transform(utf8.decoder).join();
    final exitCode = await process.exitCode;

    return FunctionResultContent(
      callId: call.id,
      content: [TextContent(output)],
      isError: exitCode != 0,
    );
  }

  // ---------------------------------------------------------------------------
  // Tool loading
  // ---------------------------------------------------------------------------

  /// Translates FunctionCall [arguments] to CLI args for a built-in coreutil.
  List<String> _builtinArgs(String name, Map<String, dynamic> arguments) =>
      switch (name) {
        'websearch' => [
            if (arguments['count'] case final int n) ...[ '-n', '$n'],
            arguments['query'] as String,
          ],
        _ => [],
      };

  /// Built-in outward tools the chatbot ships with — declared by default.
  List<FunctionDefinition> _builtinTools() => [
        FunctionDefinition(
          name: 'websearch',
          description:
              'Search the web and return a list of results. Use when the '
              'question requires current or external information not available '
              'offline.',
          inputSchema: {
            'type': 'object',
            'properties': {
              'query': {
                'type': 'string',
                'description': 'The search query.',
              },
              'count': {
                'type': 'integer',
                'description':
                    'Number of results to return (1–25). Omit to use the default (10).',
                'minimum': 1,
                'maximum': 25,
              },
            },
            'required': ['query'],
          },
        ),
      ];

  /// Resolves [name] to an absolute path by scanning PATH, or returns null.
  String? _resolveOnPath(String name) {
    final pathVar = Platform.environment['PATH'] ?? '';
    for (final dir in pathVar.split(':')) {
      if (dir.isEmpty) continue;
      final candidate = File('$dir/$name');
      if (candidate.existsSync()) return candidate.path;
    }
    return null;
  }

  /// Loads [FunctionDefinition]s from *.json files in [dir].
  List<FunctionDefinition> _loadTools(String dir) {
    final d = Directory(dir);
    if (!d.existsSync()) return const [];
    return d
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .map((f) {
          final json =
              jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
          return FunctionDefinition(
            name: json['name'] as String,
            description: json['description'] as String,
            inputSchema: json['inputSchema'] as Map<String, dynamic>,
          );
        })
        .toList();
  }
}
