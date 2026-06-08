/// Tests for the generation flags (-s/--system, -t/--max-tokens, --temperature)
/// parsed by LlmBaseCommand and surfaced as systemMessages / ioConfig.
///
/// We mirror LlmBaseCommand's ArgParser in isolation so tests are pure and fast
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
}
