/// The lens — the one thing the client invents.
///
/// Below it the transcript speaks the LLM's ontology, faithfully: a function
/// result rides as a `user` message because that is what the wire says. Printing
/// that raw puts `user: ← call_R399…` in front of a person who never said it.
/// Whoever spoke was the executor, and translating from the ontology of the
/// machine into the ontology of the person is exactly what a view is.
///
/// `chat-render` is not asked to do this: it renders the LLM's ontology
/// correctly, and correctness there is fidelity. The translation lives here.
library;

import 'package:chat_inference/chat_inference.dart';

import 'session.dart';

/// Which reading of the one transcript is on screen.
enum Lens {
  /// You and the agent. A call collapses to one line, reasoning is hidden, and
  /// the constitution is not a turn.
  conversation,

  /// The machinery: calls with their arguments, results whole, reasoning shown.
  work,

  /// Act, actor, sha — the primitive's own log, unretold.
  audit,
}

/// Who a person understands to have spoken. Never the wire's `role`.
enum Speaker {
  you('you'),
  agent('agent'),
  executor('executor'),
  constitution('system');

  const Speaker(this.label);
  final String label;
}

/// The attribution rule, alone and testable: a message's speaker is read off
/// what it carries, never off the role it travels under.
Speaker speakerOf(ChatMessage message) {
  if (message.content.any((c) => c is FunctionResultContent)) {
    return Speaker.executor;
  }
  return switch (message.role) {
    ChatRole.system => Speaker.constitution,
    ChatRole.assistant => Speaker.agent,
    ChatRole.user => Speaker.you,
  };
}

/// Render a transcript under a lens. Returns the lines a person reads.
List<String> renderTranscript(List<StoredMessage> transcript, Lens lens) {
  final lines = <String>[];
  for (final stored in transcript) {
    final speaker = speakerOf(stored.message);
    if (lens == Lens.conversation && speaker == Speaker.constitution) continue;
    final blocks = _blocks(stored.message, lens);
    if (blocks.isEmpty) continue;
    lines.add('${speaker.label}: ${blocks.first}');
    for (final extra in blocks.skip(1)) {
      lines.add('${' ' * (speaker.label.length + 2)}$extra');
    }
  }
  return lines;
}

List<String> _blocks(ChatMessage message, Lens lens) {
  final out = <String>[];
  for (final content in message.content) {
    final rendered = switch (content) {
      TextContent(:final text) => text.trim().isEmpty ? null : text.trim(),
      ThinkingContent(:final text) =>
        lens == Lens.conversation ? null : '(thinking) ${text.trim()}',
      RedactedThinkingContent() =>
        lens == Lens.conversation ? null : '(thinking, redacted)',
      FunctionCallContent(:final name, :final arguments) =>
        '→ $name(${_arguments(arguments, lens)})',
      FunctionResultContent() => '← ${_result(content, lens)}',
      BinaryContent(:final mimeType) => '($mimeType)',
      _ => null,
    };
    if (rendered != null) out.add(rendered);
  }
  return out;
}

String _arguments(Map<String, dynamic> arguments, Lens lens) {
  final spelled = arguments.entries
      .map((e) => '${e.key}: ${e.value}')
      .join(', ');
  return lens == Lens.conversation ? _clip(spelled, 60) : spelled;
}

String _result(FunctionResultContent result, Lens lens) {
  final text = result.content
      .whereType<TextContent>()
      .map((c) => c.text)
      .join()
      .trim();
  final body = lens == Lens.conversation ? _clip(text, 60) : text;
  return result.isError ? 'failed · $body' : body;
}

String _clip(String text, int width) {
  final flat = text.replaceAll('\n', ' ').trim();
  return flat.length <= width ? flat : '${flat.substring(0, width)}…';
}
