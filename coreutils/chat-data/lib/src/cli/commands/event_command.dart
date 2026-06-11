/// `chat-data event` — construct ChatEvent frames and emit as JSONL.
///
/// Grammar: one or more positional args, each describing one event.
/// Format: `type` or `type:value` (no spaces around the colon).
///
/// Supported tokens:
///   text_start             → TextStart(index:0)
///   text_delta:TEXT        → TextDelta(index:0, text:TEXT)
///   text_stop              → TextStop(index:0)
///   thinking_start              → ThinkingStart(index:0)
///   thinking_delta:TEXT         → ThinkingDelta(index:0, text:TEXT)
///   signature_delta:SIG         → SignatureDelta(index:0, signature:SIG)
///   thinking_stop               → ThinkingStop(index:0)
///   fn_start:ID:NAME            → FunctionCallStart(index:0, id:ID, name:NAME)
///   fn_args:JSON                → FunctionArgsDelta(index:0, partialJson:JSON)
///   fn_stop                     → FunctionCallStop(index:0)
///   block:TEXT                  → Block(index:0, content:TextContent) — non-streaming
///   block_fn:ID:NAME:ARGS_JSON  → Block(index:0, content:FunctionCallContent)
///   complete                    → Complete with a minimal stub metadata
///   complete:MODEL:REASON       → Complete with model=MODEL, stopReason by name
///   complete:MODEL:REASON:IN:OUT           → Complete with usage (inputTokens, outputTokens)
///   complete:MODEL:REASON:IN:OUT:REASONING → Complete with usage incl. reasoningTokens
///
/// Index is always 0 in the positional shorthand — sufficient for fixtures.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:bentos_userland/chat.dart';

class EventCommand extends Command<int> {
  // Injectable for testing.
  StringSink? out;

  @override
  String get name => 'event';

  @override
  String get description =>
      'Construct ChatEvent frames and emit each as a JSONL line on stdout.\n'
      'Args are positional tokens: type or type:value. See README for the grammar.';

  @override
  String get invocation => 'chat-data event <token> [<token>…]';

  @override
  Future<int> run() async {
    final tokens = argResults!.rest;
    if (tokens.isEmpty) {
      throw UsageException('at least one event token is required', usage);
    }

    final sink = out ?? stdout;
    for (final token in tokens) {
      final ChatEvent event;
      try {
        event = _parseToken(token);
      } on FormatException catch (e) {
        stderr.writeln('chat-data event: malformed token "$token" — $e');
        return 64;
      }
      sink.writeln(encodeEventJson(event));
    }
    return 0;
  }
}

ChatEvent _parseToken(String token) {
  final colon = token.indexOf(':');
  final type = colon < 0 ? token : token.substring(0, colon);
  final rest = colon < 0 ? '' : token.substring(colon + 1);

  return switch (type) {
    'text_start' => const TextStart(0),
    'text_delta' => TextDelta(index: 0, text: rest),
    'text_stop' => const TextStop(0),
    'thinking_start' => const ThinkingStart(0),
    'thinking_delta' => ThinkingDelta(index: 0, text: rest),
    'signature_delta' => SignatureDelta(index: 0, signature: rest),
    'thinking_stop' => const ThinkingStop(0),
    'fn_start' => _parseFnStart(rest),
    'fn_args' => FunctionArgsDelta(index: 0, partialJson: rest),
    'fn_stop' => const FunctionCallStop(0),
    'block' => _parseBlock(rest),
    'block_fn' => _parseBlockFn(rest),
    'complete' => _parseComplete(rest),
    _ => throw FormatException('unknown event type "$type"'),
  };
}

FunctionCallStart _parseFnStart(String rest) {
  // rest = "ID:NAME" — split on first colon only
  final sep = rest.indexOf(':');
  if (sep < 0) throw FormatException('fn_start requires ID:NAME — got "$rest"');
  return FunctionCallStart(
    index: 0,
    id: rest.substring(0, sep),
    name: rest.substring(sep + 1),
  );
}

Block _parseBlock(String rest) {
  // block:TEXT — text block at index 0 (non-streaming mode)
  return Block(index: 0, content: TextContent(rest));
}

Block _parseBlockFn(String rest) {
  // block_fn:ID:NAME:ARGS_JSON — function-call block at index 0
  final p1 = rest.indexOf(':');
  if (p1 < 0) throw FormatException('block_fn requires ID:NAME:JSON — got "$rest"');
  final id = rest.substring(0, p1);
  final p2 = rest.indexOf(':', p1 + 1);
  if (p2 < 0) throw FormatException('block_fn requires ID:NAME:JSON — got "$rest"');
  final name = rest.substring(p1 + 1, p2);
  final argsJson = rest.substring(p2 + 1);
  Map<String, dynamic> args;
  try {
    final decoded = jsonDecode(argsJson);
    args = decoded is Map ? decoded.cast<String, dynamic>() : {};
  } catch (_) {
    args = {};
  }
  return Block(index: 0, content: FunctionCallContent(id: id, name: name, arguments: args));
}

Complete _parseComplete(String rest) {
  if (rest.isEmpty) {
    return Complete(ChatMetadata(model: 'stub', stopReason: const EndTurn()));
  }
  // rest = "MODEL:REASON" or "MODEL:REASON:IN:OUT" (with optional usage)
  final parts = rest.split(':');
  final model = parts[0];
  final reason = _parseStopReason(parts.length > 1 ? parts[1] : '');
  TokenUsage? usage;
  if (parts.length >= 4) {
    usage = TokenUsage(
      inputTokens: int.tryParse(parts[2]) ?? 0,
      outputTokens: int.tryParse(parts[3]) ?? 0,
      reasoningTokens: parts.length > 4 ? int.tryParse(parts[4]) : null,
    );
  }
  return Complete(ChatMetadata(model: model, stopReason: reason, usage: usage));
}

ChatStopReason _parseStopReason(String s) => switch (s) {
      'max_tokens' => const MaxTokens(),
      'stop_sequence' => const StopSequence(),
      'function_call' => const FunctionCall(),
      'content_filter' => const ContentFilter(),
      _ => const EndTurn(),
    };
