/// Tests for the generation flags (-s/--system, -t/--max-tokens, --temperature)
/// parsed by LlmBaseCommand, and the scriptable-register flags
/// (--{input,output}-format, --{input,output}-encoding, --output-mode)
/// parsed by PromptCommand, surfaced as systemMessages / ioConfig.
///
/// We mirror the ArgParser in isolation so tests are pure and fast
/// — no device boot, no network, no runner overhead.
library;

import 'package:args/args.dart';
import 'package:chat_inference/chat_inference.dart';
import 'package:test/test.dart';

ArgParser _buildArgParser() {
  return ArgParser()
    ..addMultiOption('system', abbr: 's')
    ..addOption('max-tokens', abbr: 't')
    ..addOption('temperature')
    ..addFlag('verbose', abbr: 'v', negatable: false)
    ..addOption('device', abbr: 'd');
}

/// Mirrors PromptCommand's extended parser (base + scriptable-register flags).
ArgParser _buildPromptArgParser() {
  return _buildArgParser()
    ..addOption('input-format', allowed: ['text', 'typed'], defaultsTo: 'text')
    ..addOption('output-format', allowed: ['text', 'typed'], defaultsTo: 'text')
    ..addOption('input-encoding',
        allowed: ['protobuf', 'json'], defaultsTo: 'protobuf')
    ..addOption('output-encoding',
        allowed: ['protobuf', 'json'], defaultsTo: 'protobuf')
    ..addOption('output-mode',
        allowed: ['streaming', 'buffered'], defaultsTo: 'streaming')
    ..addMultiOption('function')
    ..addOption('function-choice');
}

FunctionChoice? _parseFunctionChoice(String? value) {
  return switch (value) {
    null => null,
    'auto' => const AutoChoice(),
    'none' => const NoneChoice(),
    _ => NamedChoice(value),
  };
}

ChatIOConfig _promptIoConfigWithFunctions(ArgResults r) {
  return _promptIoConfig(r).copyWith(
    functionChoice: _parseFunctionChoice(r['function-choice'] as String?),
  );
}

List<ChatMessage> _systemMessages(ArgResults r) {
  final segments = r['system'] as List<String>;
  if (segments.isEmpty) return const [];
  return [ChatMessage.systemText(segments.join('\n'))];
}

ChatIOConfig _ioConfig(ArgResults r) {
  final maxTokensStr = r['max-tokens'] as String?;
  final temperatureStr = r['temperature'] as String?;
  return ChatIOConfig(
    maxTokens: maxTokensStr != null ? int.tryParse(maxTokensStr) : null,
    temperature:
        temperatureStr != null ? double.tryParse(temperatureStr) : null,
  );
}

/// Mirrors PromptCommand.ioConfig: base config + all scriptable-register flags.
ChatIOConfig _promptIoConfig(ArgResults r) {
  final inputFmt = (r['input-format'] as String) == 'typed'
      ? Format.structured
      : Format.unstructured;
  final outputFmt = (r['output-format'] as String) == 'typed'
      ? Format.structured
      : Format.unstructured;
  final bool streaming = (r['output-mode'] as String) == 'streaming';
  return _ioConfig(r).copyWith(
    inputFormat: inputFmt,
    outputFormat: outputFmt,
    streaming: streaming,
  );
}

void main() {
  final parser = _buildArgParser();

  group('--system / -s flag', () {
    test('absent → empty list', () {
      final r = parser.parse([]);
      expect(_systemMessages(r), isEmpty);
    });

    test('single segment becomes one system message', () {
      final r = parser.parse(['-s', 'be terse']);
      final msgs = _systemMessages(r);
      expect(msgs, hasLength(1));
      expect(msgs.first.role, ChatRole.system);
      final text = (msgs.first.content.first as TextContent).text;
      expect(text, 'be terse');
    });

    test('multiple segments are joined in order with a newline', () {
      final r = parser.parse(['-s', 'line one', '-s', 'line two']);
      final msgs = _systemMessages(r);
      expect(msgs, hasLength(1));
      final text = (msgs.first.content.first as TextContent).text;
      expect(text, 'line one\nline two');
    });
  });

  group('--max-tokens / -t flag', () {
    test('absent → maxTokens is null', () {
      final r = parser.parse([]);
      expect(_ioConfig(r).maxTokens, isNull);
    });

    test('integer value is parsed', () {
      final r = parser.parse(['-t', '128']);
      expect(_ioConfig(r).maxTokens, 128);
    });

    test('invalid value yields null (no crash)', () {
      final r = parser.parse(['-t', 'abc']);
      expect(_ioConfig(r).maxTokens, isNull);
    });
  });

  group('--temperature flag', () {
    test('absent → temperature is null', () {
      final r = parser.parse([]);
      expect(_ioConfig(r).temperature, isNull);
    });

    test('float value is parsed', () {
      final r = parser.parse(['--temperature', '0.7']);
      expect(_ioConfig(r).temperature, closeTo(0.7, 0.001));
    });

    test('invalid value yields null (no crash)', () {
      final r = parser.parse(['--temperature', 'hot']);
      expect(_ioConfig(r).temperature, isNull);
    });
  });

  group('combined flags', () {
    test('all three flags coexist cleanly', () {
      final r = parser.parse([
        '-s', 'you are a poet',
        '-t', '50',
        '--temperature', '0.9',
      ]);
      final msgs = _systemMessages(r);
      final cfg = _ioConfig(r);
      expect(msgs, hasLength(1));
      expect(cfg.maxTokens, 50);
      expect(cfg.temperature, closeTo(0.9, 0.001));
    });
  });

  group('--input-format flag (PromptCommand)', () {
    final promptParser = _buildPromptArgParser();

    test('absent → inputFormat unstructured (text default)', () {
      final r = promptParser.parse([]);
      expect(_promptIoConfig(r).inputFormat, Format.unstructured);
    });

    test('text → inputFormat unstructured', () {
      final r = promptParser.parse(['--input-format', 'text']);
      expect(_promptIoConfig(r).inputFormat, Format.unstructured);
    });

    test('typed → inputFormat structured', () {
      final r = promptParser.parse(['--input-format', 'typed']);
      expect(_promptIoConfig(r).inputFormat, Format.structured);
    });

    test('typed coexists with generation flags', () {
      final r = promptParser.parse([
        '--input-format', 'typed',
        '-t', '256',
        '--temperature', '0.5',
      ]);
      final cfg = _promptIoConfig(r);
      expect(cfg.inputFormat, Format.structured);
      expect(cfg.maxTokens, 256);
      expect(cfg.temperature, closeTo(0.5, 0.001));
    });

    test('invalid value is rejected by the parser', () {
      expect(() => promptParser.parse(['--input-format', 'csv']),
          throwsA(isA<Exception>()));
    });
  });

  group('--output-format flag (PromptCommand)', () {
    final promptParser = _buildPromptArgParser();

    test('absent → outputFormat unstructured (text default)', () {
      final r = promptParser.parse([]);
      expect(_promptIoConfig(r).outputFormat, Format.unstructured);
    });

    test('text → outputFormat unstructured', () {
      final r = promptParser.parse(['--output-format', 'text']);
      expect(_promptIoConfig(r).outputFormat, Format.unstructured);
    });

    test('typed → outputFormat structured', () {
      final r = promptParser.parse(['--output-format', 'typed']);
      expect(_promptIoConfig(r).outputFormat, Format.structured);
    });

    test('invalid value is rejected by the parser', () {
      expect(() => promptParser.parse(['--output-format', 'xml']),
          throwsA(isA<Exception>()));
    });
  });

  group('--input-encoding flag (PromptCommand)', () {
    final promptParser = _buildPromptArgParser();

    test('absent → protobuf default', () {
      final r = promptParser.parse([]);
      expect(r['input-encoding'], 'protobuf');
    });

    test('jsonl is accepted', () {
      final r = promptParser.parse(['--input-encoding', 'json']);
      expect(r['input-encoding'], 'json');
    });

    test('protobuf is accepted', () {
      final r = promptParser.parse(['--input-encoding', 'protobuf']);
      expect(r['input-encoding'], 'protobuf');
    });

    test('invalid value is rejected by the parser', () {
      expect(() => promptParser.parse(['--input-encoding', 'bson']),
          throwsA(isA<Exception>()));
    });

    test('encoding coexists with typed input format', () {
      final r = promptParser.parse([
        '--input-format', 'typed',
        '--input-encoding', 'json',
      ]);
      expect(_promptIoConfig(r).inputFormat, Format.structured);
      expect(r['input-encoding'], 'json');
    });
  });

  group('--output-encoding flag (PromptCommand)', () {
    final promptParser = _buildPromptArgParser();

    test('absent → protobuf default', () {
      final r = promptParser.parse([]);
      expect(r['output-encoding'], 'protobuf');
    });

    test('jsonl is accepted', () {
      final r = promptParser.parse(['--output-encoding', 'json']);
      expect(r['output-encoding'], 'json');
    });

    test('protobuf is accepted', () {
      final r = promptParser.parse(['--output-encoding', 'protobuf']);
      expect(r['output-encoding'], 'protobuf');
    });

    test('invalid value is rejected by the parser', () {
      expect(() => promptParser.parse(['--output-encoding', 'toml']),
          throwsA(isA<Exception>()));
    });

    test('encoding coexists with typed output format', () {
      final r = promptParser.parse([
        '--output-format', 'typed',
        '--output-encoding', 'json',
      ]);
      expect(_promptIoConfig(r).outputFormat, Format.structured);
      expect(r['output-encoding'], 'json');
    });
  });

  group('--output-mode flag (PromptCommand)', () {
    final promptParser = _buildPromptArgParser();

    test('absent → streaming (default)', () {
      expect(_promptIoConfig(promptParser.parse([])).streaming, isTrue);
    });

    test('streaming → streaming on', () {
      final r = promptParser.parse(['--output-mode', 'streaming']);
      expect(_promptIoConfig(r).streaming, isTrue);
    });

    test('buffered → streaming off', () {
      final r = promptParser.parse(['--output-mode', 'buffered']);
      expect(_promptIoConfig(r).streaming, isFalse);
    });

    test('buffered with typed output and jsonl encoding coexist', () {
      final r = promptParser.parse([
        '--output-format', 'typed',
        '--output-encoding', 'json',
        '--output-mode', 'buffered',
      ]);
      final cfg = _promptIoConfig(r);
      expect(cfg.outputFormat, Format.structured);
      expect(cfg.streaming, isFalse);
      expect(r['output-encoding'], 'json');
    });

    test('streaming is independent of output format', () {
      expect(
        _promptIoConfig(
                promptParser.parse(['--output-format', 'typed'])).streaming,
        isTrue,
        reason: 'streaming is on by default even for typed output',
      );
    });

    test('invalid value is rejected by the parser', () {
      expect(() => promptParser.parse(['--output-mode', 'batch']),
          throwsA(isA<Exception>()));
    });
  });

  group('full scriptable-register combination', () {
    final promptParser = _buildPromptArgParser();

    test('typed in+out, jsonl encoding, buffered, with generation flags', () {
      final r = promptParser.parse([
        '--input-format', 'typed',
        '--input-encoding', 'json',
        '--output-format', 'typed',
        '--output-encoding', 'json',
        '--output-mode', 'buffered',
        '-t', '1024',
        '--temperature', '0.2',
      ]);
      final cfg = _promptIoConfig(r);
      expect(cfg.inputFormat, Format.structured);
      expect(cfg.outputFormat, Format.structured);
      expect(cfg.streaming, isFalse);
      expect(cfg.maxTokens, 1024);
      expect(cfg.temperature, closeTo(0.2, 0.001));
      expect(r['input-encoding'], 'json');
      expect(r['output-encoding'], 'json');
    });

    test('text format, encoding flag present but silently ignored by design', () {
      // encoding is only honoured when format=typed; text+protobuf is not an error.
      final r = promptParser.parse([
        '--output-format', 'text',
        '--output-encoding', 'protobuf',
      ]);
      final cfg = _promptIoConfig(r);
      expect(cfg.outputFormat, Format.unstructured);
      // The encoding flag is parsed without error — the coreutil ignores it.
      expect(r['output-encoding'], 'protobuf');
    });
  });

  group('--function-choice flag (PromptCommand)', () {
    final promptParser = _buildPromptArgParser();

    test('absent → functionChoice is null', () {
      final r = promptParser.parse([]);
      expect(_promptIoConfigWithFunctions(r).functionChoice, isNull);
    });

    test('auto → AutoChoice', () {
      final r = promptParser.parse(['--function-choice', 'auto']);
      expect(_promptIoConfigWithFunctions(r).functionChoice, isA<AutoChoice>());
    });

    test('none → NoneChoice', () {
      final r = promptParser.parse(['--function-choice', 'none']);
      expect(_promptIoConfigWithFunctions(r).functionChoice, isA<NoneChoice>());
    });

    test('named function → NamedChoice with correct name', () {
      final r = promptParser.parse(['--function-choice', 'get_weather']);
      final choice = _promptIoConfigWithFunctions(r).functionChoice;
      expect(choice, isA<NamedChoice>());
      expect((choice as NamedChoice).name, 'get_weather');
    });

    test('function-choice coexists with output-format and generation flags', () {
      final r = promptParser.parse([
        '--output-format', 'typed',
        '--function-choice', 'auto',
        '-t', '256',
      ]);
      final cfg = _promptIoConfigWithFunctions(r);
      expect(cfg.outputFormat, Format.structured);
      expect(cfg.functionChoice, isA<AutoChoice>());
      expect(cfg.maxTokens, 256);
    });
  });
}
