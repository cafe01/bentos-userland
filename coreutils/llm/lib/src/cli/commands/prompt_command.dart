/// `llm <prompt>` — the default command: stream one answer and exit.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:bentos_userland/bentos_userland.dart';
import 'package:bentos_userland/chat.dart';

import '../../function_file.dart';
import 'llm_base_command.dart';

class PromptCommand extends LlmBaseCommand {
  PromptCommand() {
    argParser
      ..addOption(
        'input-format',
        allowed: ['text', 'jsonl'],
        defaultsTo: 'text',
        help: 'Input mode. '
            'text (default): stdin or arg is a single user prompt. '
            'jsonl: stdin is a conversation — one ChatMessage (proto3 JSON) per line.',
      )
      ..addOption(
        'output-format',
        allowed: ['text', 'jsonl'],
        defaultsTo: 'text',
        help: 'Output mode. '
            'text (default): stream the answer as plain text. '
            'jsonl: emit the assembled assistant ChatMessage as one JSON line.',
      )
      ..addFlag(
        'stream',
        defaultsTo: true,
        help: 'Stream tokens as generated. '
            'Defaults on for text output, off for jsonl output. '
            'Use --no-stream to force whole-message-at-once.',
      )
      ..addMultiOption(
        'function',
        help: 'Declare a callable function from a JSON file '
            '({"name","description","inputSchema"}). Repeatable. '
            'Requires --output-format jsonl.',
        valueHelp: 'file.json',
      )
      ..addOption(
        'function-choice',
        help: 'Constrain which function the model may call. '
            'auto: model decides (default when functions are set). '
            'none: model must not call any function. '
            'Any other value: model must call the named function.',
        valueHelp: 'auto|none|name',
      );
  }

  @override
  String get name => 'prompt';

  @override
  String get description =>
      'Stream one answer and exit (the default command). With no prompt arg '
      'and piped stdin, the prompt is read from stdin.';

  @override
  String get invocation =>
      'llm [-d <device>] [-s <system>]... [-t <n>] [--temperature <f>] [-v] <prompt>\n'
      '  or: echo … | llm\n'
      '  or: cat messages.jsonl | llm --input-format jsonl --output-format jsonl';

  /// Extends the base config with the scriptable-register flags.
  /// File loading (--function) and output-format validation happen in run().
  @override
  ChatIOConfig get ioConfig {
    final inputFmt = (argResults!['input-format'] as String) == 'jsonl'
        ? Format.structured
        : Format.unstructured;
    final outputFmt = (argResults!['output-format'] as String) == 'jsonl'
        ? Format.structured
        : Format.unstructured;

    // streaming: explicit --stream/--no-stream wins; otherwise default is on
    // for text output and off for jsonl output (the filter use-case wants the
    // assembled message, not a token stream).
    final bool streaming;
    if (argResults!.wasParsed('stream')) {
      streaming = argResults!['stream'] as bool;
    } else {
      streaming = outputFmt == Format.unstructured;
    }

    return super.ioConfig.copyWith(
      inputFormat: inputFmt,
      outputFormat: outputFmt,
      streaming: streaming,
      functionChoice: _parseFunctionChoice(
        argResults!['function-choice'] as String?,
      ),
    );
  }

  /// Maps the --function-choice string to a FunctionChoice variant.
  /// null → null (absent flag). 'auto' / 'none' / name → typed variant.
  static FunctionChoice? _parseFunctionChoice(String? value) {
    return switch (value) {
      null => null,
      'auto' => const AutoChoice(),
      'none' => const NoneChoice(),
      _ => NamedChoice(value),
    };
  }

  /// Wraps [loadFunctionDefinitionFromFile], converting domain exceptions to
  /// [UsageException] so the CLI runner prints them cleanly.
  FunctionDefinition _loadFunctionFile(String path) {
    try {
      return loadFunctionDefinitionFromFile(path);
    } on ArgumentError catch (e) {
      throw UsageException('--function: ${e.message}', usage);
    } on FormatException catch (e) {
      throw UsageException('--function: malformed JSON in $path — $e', usage);
    }
  }

  @override
  Future<int> run() async {
    final consumer = await bootConsumer();
    if (consumer == null) return 3;

    // Load --function files before resolving messages so the error surfaces early.
    final functionPaths = argResults!['function'] as List<String>;
    final functions =
        functionPaths.isEmpty ? null : functionPaths.map(_loadFunctionFile).toList();

    var config = ioConfig;
    final isJsonlInput = config.inputFormat == Format.structured;
    final isJsonlOutput = config.outputFormat == Format.structured;

    if (functions != null && !isJsonlOutput) {
      throw UsageException(
        '--function requires --output-format jsonl '
        '(function calls cannot be serialized in text mode)',
        usage,
      );
    }

    if (functions != null) {
      config = config.copyWith(functions: functions);
    }

    final messages = isJsonlInput
        ? await _resolveJsonlMessages(argResults!.rest)
        : await _resolveTextMessages(argResults!.rest);
    if (messages == null) return 64; // usage error already reported

    try {
      if (isJsonlOutput) {
        await consumer.filterTurn(
          messages,
          systemMessages: systemMessages,
          config: config,
          verbose: verbose,
        );
      } else {
        await consumer.streamTurn(
          messages,
          systemMessages: systemMessages,
          config: config,
          verbose: verbose,
        );
      }
    } on BentosException catch (e) {
      stderr.writeln('llm: $e');
      return 1;
    }
    return 0;
  }

  /// text mode: arg or piped stdin → single userText message.
  Future<List<ChatMessage>?> _resolveTextMessages(List<String> rest) async {
    String? prompt;
    if (rest.isNotEmpty) {
      prompt = rest.join(' ');
    } else if (!stdin.hasTerminal) {
      prompt = (await stdin.transform(systemEncoding.decoder).join()).trim();
    }
    if (prompt == null || prompt.isEmpty) {
      throw UsageException('a prompt is required', usage);
    }
    return [ChatMessage.userText(prompt)];
  }

  /// jsonl mode: stdin is a conversation — one ChatMessage per non-empty line.
  /// Positional args are rejected (they would be silently ignored otherwise).
  Future<List<ChatMessage>?> _resolveJsonlMessages(List<String> rest) async {
    if (rest.isNotEmpty) {
      throw UsageException(
        '--input-format jsonl reads from stdin; positional args are not accepted',
        usage,
      );
    }
    if (stdin.hasTerminal) {
      throw UsageException(
        '--input-format jsonl requires piped stdin (no terminal)',
        usage,
      );
    }
    final lines = await stdin
        .transform(systemEncoding.decoder)
        .transform(const LineSplitter())
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      stderr.writeln('llm: --input-format jsonl: empty input');
      return null;
    }
    try {
      return lines.map(decodeMessageJson).toList();
    } on FormatException catch (e) {
      stderr.writeln('llm: --input-format jsonl: malformed line — $e');
      return null;
    }
  }
}
