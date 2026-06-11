/// Tests for the generation flags (-s/--system, -t/--max-tokens, --temperature,
/// --input-format) parsed by LlmBaseCommand / PromptCommand and surfaced as
/// systemMessages / ioConfig.
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
    ..addOption('input-format', allowed: ['text', 'jsonl'], defaultsTo: 'text')
    ..addOption('output-format', allowed: ['text', 'jsonl'], defaultsTo: 'text')
    ..addFlag('stream', defaultsTo: true)
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
  final inputFmt = (r['input-format'] as String) == 'jsonl'
      ? Format.structured
      : Format.unstructured;
  final outputFmt = (r['output-format'] as String) == 'jsonl'
      ? Format.structured
      : Format.unstructured;
  // streaming: on by default regardless of output format.
  final bool streaming = r['stream'] as bool;
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

    test('jsonl → inputFormat structured', () {
      final r = promptParser.parse(['--input-format', 'jsonl']);
      expect(_promptIoConfig(r).inputFormat, Format.structured);
    });

    test('jsonl coexists with generation flags', () {
      final r = promptParser.parse([
        '--input-format', 'jsonl',
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

    test('jsonl → outputFormat structured', () {
      final r = promptParser.parse(['--output-format', 'jsonl']);
      expect(_promptIoConfig(r).outputFormat, Format.structured);
    });

    test('invalid value is rejected by the parser', () {
      expect(() => promptParser.parse(['--output-format', 'xml']),
          throwsA(isA<Exception>()));
    });
  });

  group('--[no-]stream flag (PromptCommand)', () {
    final promptParser = _buildPromptArgParser();

    test('absent → streaming on (default, all output formats)', () {
      expect(_promptIoConfig(promptParser.parse([])).streaming, isTrue);
      expect(
        _promptIoConfig(promptParser.parse(['--output-format', 'jsonl']))
            .streaming,
        isTrue,
        reason: 'streaming is on by default even for jsonl output',
      );
    });

    test('explicit --no-stream → streaming off', () {
      final r = promptParser.parse(['--no-stream']);
      expect(_promptIoConfig(r).streaming, isFalse);
    });

    test('explicit --no-stream with jsonl output → streaming off', () {
      final r = promptParser.parse(['--output-format', 'jsonl', '--no-stream']);
      expect(_promptIoConfig(r).streaming, isFalse);
    });

    test('jsonl in+out both structured, streaming on by default', () {
      final r = promptParser.parse([
        '--input-format', 'jsonl',
        '--output-format', 'jsonl',
      ]);
      final cfg = _promptIoConfig(r);
      expect(cfg.inputFormat, Format.structured);
      expect(cfg.outputFormat, Format.structured);
      expect(cfg.streaming, isTrue);
    });

    test('full filter flags coexist with generation flags', () {
      final r = promptParser.parse([
        '--input-format', 'jsonl',
        '--output-format', 'jsonl',
        '-t', '1024',
        '--temperature', '0.2',
      ]);
      final cfg = _promptIoConfig(r);
      expect(cfg.inputFormat, Format.structured);
      expect(cfg.outputFormat, Format.structured);
      expect(cfg.streaming, isTrue);
      expect(cfg.maxTokens, 1024);
      expect(cfg.temperature, closeTo(0.2, 0.001));
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
        '--output-format', 'jsonl',
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
