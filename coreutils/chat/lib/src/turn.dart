import 'dart:convert';
import 'dart:io';

import 'package:bentos_userland/chat.dart';

/// A message produced mid-turn, handed to the caller to persist (one `tx`
/// append per mutation) and to append to the live conversation.
typedef MessageSink = Future<void> Function(ChatMessage message);

/// The agent loop for ONE turn — harvested from the chatbot, with the REPL and
/// SessionStore stripped out. Inference + tool dispatch live here (the *eval*
/// of a single turn); the loop *between* turns is the shell's.
final class Turn {
  Turn({
    required this.device,
    required this.systemMessages,
    required this.config,
    required this.toolsDir,
    required this.verbose,
    required this.persist,
  });

  static const _maxToolIter = 20;

  final BentosChatDevice device;
  final List<ChatMessage> systemMessages;
  final ChatIOConfig config;
  final String? toolsDir;
  final bool verbose;

  /// Persists each message as it is produced (assistant reactions, tool
  /// results) — the write-ahead `tx append` per mutation.
  final MessageSink persist;

  /// Runs the tool-dispatch loop, mutating [conversation] in place and
  /// persisting every message it adds. The user message must already be in
  /// [conversation] and already committed (write-ahead) before this is called.
  Future<void> run(List<ChatMessage> conversation) async {
    for (var iter = 0; iter < _maxToolIter; iter++) {
      final assistantMsg = await _streamTurn(conversation);
      conversation.add(assistantMsg);
      await persist(assistantMsg);

      final calls =
          assistantMsg.content.whereType<FunctionCallContent>().toList();
      if (calls.isEmpty) return;

      // Dispatch every call in this turn in parallel.
      final results =
          await Future.wait(calls.map((c) => _dispatch(c)));
      // All results in ONE domain message — the subsystem contract; the driver
      // expands N results → N wire messages internally.
      final resultMsg = ChatMessage(role: ChatRole.user, content: results);
      conversation.add(resultMsg);
      await persist(resultMsg);
    }
    stderr.writeln('chat: stop-guard reached ($_maxToolIter tool iterations)');
  }

  /// One inference turn, streaming text deltas to stdout; returns the full
  /// assembled assistant message (text + any function-call blocks).
  Future<ChatMessage> _streamTurn(List<ChatMessage> messages) async {
    final wire = [...systemMessages, ...messages];
    final textBufs = <int, StringBuffer>{};
    final blockContents = <int, ChatContent>{};

    await for (final event in device.infer(wire, config).foldFunctionCalls()) {
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

  /// Invokes one tool: built-in coreutils speak CLI args (resolved on PATH),
  /// tools in an explicit dir speak JSON-on-stdin.
  Future<FunctionResultContent> _dispatch(FunctionCallContent call) async {
    String? toolPath;
    if (toolsDir != null) {
      final candidate = '$toolsDir/${call.name}';
      if (File(candidate).existsSync()) toolPath = candidate;
    }
    toolPath ??= _resolveOnPath(call.name);

    if (toolPath == null) {
      stderr.writeln('chat: tool not found: ${call.name}');
      return FunctionResultContent(
        callId: call.id,
        content: [TextContent('tool not found: ${call.name}')],
        isError: true,
      );
    }

    final isBuiltin = toolsDir == null ||
        !File('$toolsDir/${call.name}').existsSync();

    final Process process;
    if (isBuiltin) {
      process = await Process.start(toolPath, _builtinArgs(call.name, call.arguments));
    } else {
      process = await Process.start(toolPath, const []);
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

  static List<String> _builtinArgs(String name, Map<String, dynamic> arguments) =>
      switch (name) {
        'websearch' => [
            if (arguments['count'] case final int n) ...['-n', '$n'],
            arguments['query'] as String,
          ],
        _ => const [],
      };

  static String? _resolveOnPath(String name) {
    final pathVar = Platform.environment['PATH'] ?? '';
    for (final dir in pathVar.split(':')) {
      if (dir.isEmpty) continue;
      final candidate = File('$dir/$name');
      if (candidate.existsSync()) return candidate.path;
    }
    return null;
  }
}

/// The outward tools `chat` ships with by default — declared every turn, so a
/// bare `chat` already reaches the web. `chat` reaches outward (query the
/// world), never inward (no shell, no filesystem mutation of the host).
List<FunctionDefinition> builtinTools() => [
      FunctionDefinition(
        name: 'websearch',
        description:
            'Search the web and return a list of results. Use when the '
            'question requires current or external information not available '
            'offline.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'query': {'type': 'string', 'description': 'The search query.'},
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

/// Loads [FunctionDefinition]s from *.json files in [dir].
List<FunctionDefinition> loadTools(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return const [];
  return d
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .map((f) {
        final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        return FunctionDefinition(
          name: json['name'] as String,
          description: json['description'] as String,
          inputSchema: json['inputSchema'] as Map<String, dynamic>,
        );
      })
      .toList();
}
