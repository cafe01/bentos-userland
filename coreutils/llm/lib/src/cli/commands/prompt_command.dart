/// `llm <prompt>` — the default command: stream one answer and exit.
library;

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
        allowed: ['text', 'typed'],
        defaultsTo: 'text',
        help: 'Input format. '
            'text (default): stdin or arg is a single user prompt. '
            'typed: stdin is a conversation — one ChatMessage frame per record.',
      )
      ..addOption(
        'output-format',
        allowed: ['text', 'typed'],
        defaultsTo: 'text',
        help: 'Output format. '
            'text (default): stream the answer as plain text. '
            'typed: emit the raw ChatEvent stream, one frame per record.',
      )
      ..addOption(
        'input-encoding',
        allowed: ['protobuf', 'json'],
        defaultsTo: 'protobuf',
        help: 'Input channel encoding (honoured when --input-format=typed). '
            'protobuf (default): length-prefix framed protobuf binary. '
            'json: proto3-JSON records.',
      )
      ..addOption(
        'output-encoding',
        allowed: ['protobuf', 'json'],
        defaultsTo: 'protobuf',
        help: 'Output channel encoding (honoured when --output-format=typed). '
            'protobuf (default): length-prefix framed binary. '
            'json: proto3-JSON records.',
      )
      ..addOption(
        'output-mode',
        allowed: ['streaming', 'buffered'],
        defaultsTo: 'streaming',
        help: 'Output mode. '
            'streaming (default): typed triads — live, per-delta events. '
            'buffered: whole-Block events only (still events, no folding).',
      )
      ..addMultiOption(
        'function',
        help: 'Declare a callable function from a JSON file '
            '({"name","description","inputSchema"}). Repeatable. '
            'Requires --output-format typed.',
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
      '  or: cat messages.jsonl | llm --input-format typed --input-encoding json '
      '--output-format typed --output-encoding json';

  /// Extends the base config with the scriptable-register flags.
  @override
  ChatIOConfig get ioConfig {
    final inputFmt = (argResults!['input-format'] as String) == 'typed'
        ? Format.structured
        : Format.unstructured;
    final outputFmt = (argResults!['output-format'] as String) == 'typed'
        ? Format.structured
        : Format.unstructured;

    final bool streaming =
        (argResults!['output-mode'] as String) == 'streaming';

    // Encoding is inert under format=text — only wire it when format=typed so
    // configToIoctls doesn't emit a spurious CHAT_SET_*_ENCODING ioctl.
    final inputEncoding = inputFmt == Format.structured
        ? ((argResults!['input-encoding'] as String) == 'json'
            ? Encoding.json
            : Encoding.protobuf)
        : Encoding.protobuf;
    final outputEncoding = outputFmt == Format.structured
        ? ((argResults!['output-encoding'] as String) == 'json'
            ? Encoding.json
            : Encoding.protobuf)
        : Encoding.protobuf;

    return super.ioConfig.copyWith(
      inputFormat: inputFmt,
      outputFormat: outputFmt,
      streaming: streaming,
      inputEncoding: inputEncoding,
      outputEncoding: outputEncoding,
      functionChoice: _parseFunctionChoice(
        argResults!['function-choice'] as String?,
      ),
    );
  }

  static FunctionChoice? _parseFunctionChoice(String? value) {
    return switch (value) {
      null => null,
      'auto' => const AutoChoice(),
      'none' => const NoneChoice(),
      _ => NamedChoice(value),
    };
  }

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

    final functionPaths = argResults!['function'] as List<String>;
    final functions =
        functionPaths.isEmpty ? null : functionPaths.map(_loadFunctionFile).toList();

    var config = ioConfig;
    final isTypedInput = config.inputFormat == Format.structured;
    final isTypedOutput = config.outputFormat == Format.structured;
    // Encoding flags are only honoured when format=typed; silently ignored otherwise.
    final inputEncoding =
        isTypedInput ? argResults!['input-encoding'] as String : 'protobuf';
    final outputEncoding =
        isTypedOutput ? argResults!['output-encoding'] as String : 'protobuf';

    if (functions != null && !isTypedOutput) {
      throw UsageException(
        '--function requires --output-format typed '
        '(function calls cannot be serialized in text mode)',
        usage,
      );
    }

    if (functions != null) {
      config = config.copyWith(functions: functions);
    }

    // Relay mode: any typed axis routes through relayTurn (zero codec on seams).
    if (isTypedInput || isTypedOutput) {
      try {
        if (isTypedInput) {
          if (stdin.hasTerminal) {
            throw UsageException(
              '--input-format typed requires piped stdin (no terminal)',
              usage,
            );
          }
          await consumer.relayTurn(
            config: config,
            inputEncoding: inputEncoding,
            outputEncoding: outputEncoding,
            typedStdin: stdin,
            systemMessages: systemMessages,
            verbose: verbose,
          );
        } else {
          // text input + typed output
          final prompt = await _resolveTextPrompt(argResults!.rest);
          if (prompt == null) return 64;
          await consumer.relayTurn(
            config: config,
            inputEncoding: inputEncoding,
            outputEncoding: outputEncoding,
            textPrompt: prompt,
            systemMessages: systemMessages,
            verbose: verbose,
          );
        }
      } on BentosException catch (e) {
        stderr.writeln('llm: $e');
        return 1;
      }
      return 0;
    }

    // Casual register: text in, text out — streamTurn via infer().
    final messages = await _resolveTextMessages(argResults!.rest);
    if (messages == null) return 64;
    try {
      await consumer.streamTurn(
        messages,
        systemMessages: systemMessages,
        config: config,
        verbose: verbose,
      );
    } on BentosException catch (e) {
      stderr.writeln('llm: $e');
      return 1;
    }
    return 0;
  }

  /// text input: arg or piped stdin → prompt string.
  Future<String?> _resolveTextPrompt(List<String> rest) async {
    String? prompt;
    if (rest.isNotEmpty) {
      prompt = rest.join(' ');
    } else if (!stdin.hasTerminal) {
      prompt = (await stdin.transform(systemEncoding.decoder).join()).trim();
    }
    if (prompt == null || prompt.isEmpty) {
      throw UsageException('a prompt is required', usage);
    }
    return prompt;
  }

  /// text mode: arg or piped stdin → single userText message.
  Future<List<ChatMessage>?> _resolveTextMessages(List<String> rest) async {
    final prompt = await _resolveTextPrompt(rest);
    if (prompt == null) return null;
    return [ChatMessage.userText(prompt)];
  }
}
