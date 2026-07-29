/// The `.llm` worktree schema — what an inference session looks like as files.
///
/// ```
/// <session>.llm/
/// ├── channel.json          the device and its knobs
/// ├── title                 the session's display name
/// └── messages/
///     └── <ulid>.json       one record: the ontology's message, plus vitals
/// ```
///
/// One file per message is what makes a transaction's diff its payload: `say`
/// adds one file, `revise` changes one, `return` extends one. The name is a
/// ULID, so a turn is addressed rather than indexed and nothing is ever
/// renamed when a turn is revised or dropped.
library;

import 'dart:convert';
import 'dart:math';

import 'package:chat_inference/chat_inference.dart';

const String channelFile = 'channel.json';
const String titleFile = 'title';
const String messagesDir = 'messages';

String messagePath(String id) => '$messagesDir/$id.json';

/// Lexicographic by name is chronological by creation, and appends to one ref
/// are serialized by the ref's compare-and-swap — so the order is total and no
/// writer needs to know how many messages there are.
final class Ulid {
  static const String _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static final Random _rng = Random();
  static int _lastMs = 0;
  static int _guard = 0;

  static String next() {
    final ms = DateTime.now().millisecondsSinceEpoch;
    if (ms == _lastMs) {
      _guard++;
    } else {
      _lastMs = ms;
      _guard = 0;
    }
    // Monotonic within the millisecond; random beyond it.
    return _base32(ms, 10) + _base32(_guard, 4) + _base32(_rng.nextInt(1 << 30), 6);
  }

  static String _base32(int value, int width) {
    var v = value;
    final out = <String>[];
    for (var i = 0; i < width; i++) {
      out.add(_crockford[v % 32]);
      v ~/= 32;
    }
    return out.reversed.join();
  }
}

/// The channel: which device, and the knobs it runs under. Held in the entity
/// because a session retunable between turns is what is wanted; a coreutil
/// passing knobs as arguments writes this same file as a `configure`.
final class Channel {
  const Channel({required this.deviceId, required this.config});

  final String deviceId;
  final ChatIOConfig config;

  String encode() => _pretty({
        'device': deviceId,
        'config': jsonDecode(encodeConfigJson(config)),
      });

  static Channel decode(String s) {
    final m = jsonDecode(s) as Map<String, dynamic>;
    return Channel(
      deviceId: m['device'] as String,
      config: decodeConfigJson(jsonEncode(m['config'])),
    );
  }
}

/// The device and effective knobs a turn ran under, frozen when the turn
/// commits — the channel stays live and moves on, this never does.
final class TurnMarker {
  const TurnMarker({required this.deviceId, required this.config});

  final String deviceId;
  final ChatIOConfig config;
}

/// One message's file: the ontology's own message, plus the two things the
/// ontology deliberately does not carry — the turn's vitals and the marker of
/// what it ran under. Composition, never duplication; and every one of the
/// three is written through the subsystem's own text codec, so the app
/// serializes nobody else's type.
final class TurnRecord {
  const TurnRecord({
    required this.id,
    required this.message,
    this.meta,
    this.marker,
  });

  /// The message's address within the session — the file's name.
  final String id;
  final ChatMessage message;
  final ChatMetadata? meta;
  final TurnMarker? marker;

  List<FunctionCallContent> get calls =>
      message.content.whereType<FunctionCallContent>().toList();

  List<FunctionResultContent> get results =>
      message.content.whereType<FunctionResultContent>().toList();

  /// A user-role message whose content is results is the executor's turn. The
  /// ontology has three roles; the session has three seats, and which seat
  /// acted is the transaction's author, never the role.
  bool get isExecutorTurn => message.role == ChatRole.user && results.isNotEmpty;

  String encode() => _pretty({
        'message': jsonDecode(encodeMessageJson(message)),
        if (meta != null) 'meta': jsonDecode(encodeMetadataJson(meta!)),
        if (marker != null)
          'marker': {
            'device': marker!.deviceId,
            'config': jsonDecode(encodeConfigJson(marker!.config)),
          },
      });

  static TurnRecord decode(String id, String s) {
    final m = jsonDecode(s) as Map<String, dynamic>;
    final markerJson = m['marker'] as Map<String, dynamic>?;
    return TurnRecord(
      id: id,
      message: decodeMessageJson(jsonEncode(m['message'])),
      meta: m['meta'] == null ? null : decodeMetadataJson(jsonEncode(m['meta'])),
      marker: markerJson == null
          ? null
          : TurnMarker(
              deviceId: markerJson['device'] as String,
              config: decodeConfigJson(jsonEncode(markerJson['config'])),
            ),
    );
  }

  TurnRecord withContent(List<ChatContent> content) => TurnRecord(
        id: id,
        message: ChatMessage(role: message.role, content: content),
        meta: meta,
        marker: marker,
      );
}

String _pretty(Object o) => '${const JsonEncoder.withIndent('  ').convert(o)}\n';
