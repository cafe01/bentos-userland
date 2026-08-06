/// The material the claims are made about.
///
/// **Provenance is the point.** `real-session/` is lifted verbatim out of a
/// conversation that actually happened — laid down by the entity's own bash
/// bodies, encoded by `chat-codec`, streamed by a vendor. Nothing in the package
/// under judgment made those bytes, so a claim that holds over them is not this
/// code agreeing with itself.
///
/// `hand/` is the complement: shapes the encoder would never emit — two results
/// in one message, a result beside a note, thinking beside a call — so that a
/// population minted by one tool cannot make a structural coincidence look like
/// a law.
library;

import 'dart:convert';
import 'dart:io';

import 'package:bentos_userland/src/llm/session/transcript.dart';
import 'package:chat_inference/chat_inference.dart';

/// Resolved against the package root, which is where `dart test` stands.
const String fixtureRoot = 'test/llm/session/fixtures';

/// The nine messages of the real session, in the order they landed:
/// system · prompt · reply(call) · result · reply(text) · prompt · reply(call)
/// · result · reply(text).
const List<String> realSessionMessages = [
  '0001-20260805T175239Z.json',
  '0002-20260805T175310Z.json',
  '0003-20260805T175339Z.jsonl',
  '0004-20260805T175340Z.json',
  '0005-20260805T175342Z.jsonl',
  '0006-20260805T184114Z.json',
  '0007-20260805T184117Z.jsonl',
  '0008-20260805T184118Z.json',
  '0009-20260805T184120Z.jsonl',
];

/// The raw bytes, keyed by the path they hold in the tree — which is what the
/// fake primitive is loaded with.
Map<String, String> realSessionTree() => {
      'llm/messages/.gitkeep': '',
      for (final name in realSessionMessages)
        'llm/messages/$name':
            File('$fixtureRoot/real-session/$name').readAsStringSync(),
    };

/// The same, decoded — for the pieces that are judged with no primitive at all.
///
/// Decoding goes through `chat_inference`, which is the library that owns
/// folding. The suite does not re-fold and the face does not either.
Future<List<StoredMessage>> realSessionTranscript() async => [
      for (final name in realSessionMessages)
        StoredMessage(
          'llm/messages/$name',
          await decodeStored(name, File('$fixtureRoot/real-session/$name').readAsStringSync()),
        ),
    ];

/// One hand-authored message, by file name under `hand/`.
Future<StoredMessage> hand(String name) async => StoredMessage(
      'llm/messages/9999-$name',
      await decodeStored(name, File('$fixtureRoot/hand/$name').readAsStringSync()),
    );

/// A `.jsonl` is an assistant's event stream; a `.json` is one message already.
Future<ChatMessage> decodeStored(String name, String body) async {
  if (!name.endsWith('.jsonl')) return decodeMessageJson(body);
  final events = const LineSplitter()
      .convert(body)
      .where((line) => line.trim().isNotEmpty)
      .map(decodeEventJson);
  return Stream<ChatEvent>.fromIterable(events).foldToMessage();
}
