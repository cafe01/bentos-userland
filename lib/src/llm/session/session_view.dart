/// The lens: the one thing the face invents.
///
/// Translation from the ontology of the machine into the ontology of the person.
/// Pure — same transcript and same lens, same turns — and it decides *what* is
/// said, never how it is laid out: indentation, colour and width belong to the
/// register.
library;

import 'dart:convert';

import 'package:chat_inference/chat_inference.dart';

import 'attribution.dart';
import 'transcript.dart';

/// How much of a call's arguments survive the conversation lens. Enough to say
/// which call it was, never enough to read it as data.
const int _collapsedArguments = 48;

final class LensedView implements TranscriptView {
  const LensedView([this.attribution = const SpeakerRule()]);

  final Attribution attribution;

  @override
  List<RenderedTurn> render(List<StoredMessage> transcript, Lens lens) {
    final turns = <RenderedTurn>[];
    for (final stored in transcript) {
      final speaker = attribution.of(stored.message);
      // The constitution is not a turn of the conversation. It is machinery,
      // and work is where machinery is shown.
      if (speaker == Speaker.constitution && lens != Lens.work) continue;

      final blocks = <String>[
        for (final content in stored.message.content)
          ...?_blocks(content, lens),
      ];
      // A message that renders to nothing produces no turn at all: a speaker
      // line over an empty body is a turn nobody took.
      if (blocks.isEmpty) continue;
      turns.add(RenderedTurn(speaker, blocks, path: stored.path));
    }
    return turns;
  }

  List<String>? _blocks(ChatContent content, Lens lens) {
    final work = lens == Lens.work;
    switch (content) {
      case TextContent(:final text):
        return text.trim().isEmpty ? null : [text];

      case ThinkingContent(:final text):
        return work ? ['thinking: $text'] : null;

      case RedactedThinkingContent():
        // Marked rather than printed: the bytes are opaque, and a work lens
        // that showed nothing would be claiming the turn had no reasoning.
        return work ? ['thinking: (redacted)'] : null;

      case FunctionCallContent(:final name, :final arguments):
        final spelled = jsonEncode(arguments);
        return [
          work
              ? '→ $name $spelled'
              : '→ $name ${_clip(spelled, _collapsedArguments)}',
        ];

      case FunctionResultContent(:final callId, :final content, :final isError):
        final body = content
            .whereType<TextContent>()
            .map((c) => c.text)
            .join('\n')
            .trim();
        if (!work) return ['← $callId${isError ? ' (failed)' : ''}'];
        return ['← $callId ${isError ? 'failed: ' : ''}$body'];

      case BinaryContent(:final mimeType):
        return ['[$mimeType]'];

      case CachePointContent():
        return null;
    }
  }

  String _clip(String text, int width) {
    final flat = text.replaceAll('\n', ' ');
    return flat.length <= width ? flat : '${flat.substring(0, width)}…';
  }
}
