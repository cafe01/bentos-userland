/// The session as the client reaches it — a coordinate, the primitive, and the
/// messages read back through the ontology.
///
/// The directory is `chat_client/` and the binary is `chat` because
/// `lib/src/chat/` is already taken by the kernel's ChatDevice binding. The
/// names diverge on purpose; nothing here touches that neighbour.
library;

import 'dart:convert';
import 'dart:io';

import 'package:chat_inference/chat_inference.dart';

/// Where a conversation is. The entity defaults to `bentos.llm`, but the client
/// is a client of any body that fuses that ontology — so the entity half is
/// spellable and never assumed.
final class Coordinate {
  const Coordinate(this.entity, this.instance, {this.place});

  /// `<entity>:<instance>` or a bare `<instance>` against the default entity.
  factory Coordinate.parse(String spec, {String? place}) {
    final parts = spec.split(':');
    if (parts.length == 1) {
      return Coordinate(defaultEntity, parts[0], place: place);
    }
    if (parts.length == 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return Coordinate(parts[0], parts[1], place: place);
    }
    throw FormatException(
      "chat: '$spec' is not a session — spell it <entity>:<instance> or "
      '<instance>',
    );
  }

  static const String defaultEntity = 'bentos.llm';

  final String entity;
  final String instance;

  /// The place the coordinate resolves from. Null means the vantage the caller
  /// is standing in, which is what `entity` already does on its own.
  final String? place;

  @override
  String toString() => '$entity:$instance';
}

/// One message as it sits in the tree, with the file it came from — the client
/// needs both, since the extension is what says whether the bytes are one
/// message or an assistant's event stream.
final class StoredMessage {
  const StoredMessage(this.path, this.message);

  final String path;
  final ChatMessage message;
}

/// The primitive, always spoken and never reimplemented: the client resolves no
/// function, reads no manifest and lays no environment. It names a verb at a
/// coordinate, exactly as a person at a terminal would.
final class Session {
  Session(this.coord);

  final Coordinate coord;

  List<String> get _at =>
      coord.place == null ? const [] : ['-C', coord.place!];

  /// `entity run <coord> <function> [args...]`, with the caller's streams. Used
  /// for the acts — the keyboard's side of the client.
  Future<int> run(String function, List<String> arguments) async {
    final child = await Process.start(
      'entity',
      [..._at, 'run', '$coord', function, ...arguments],
      mode: ProcessStartMode.inheritStdio,
    );
    return child.exitCode;
  }

  /// The same, captured. A function whose whole output is an answer — `fold`
  /// above all — is read rather than shown.
  Future<ProcessResult> capture(String function, List<String> arguments) {
    return Process.run('entity', [..._at, 'run', '$coord', function,
      ...arguments]);
  }

  /// The state word the entity itself folds: `idle`, `owes_inference`,
  /// `owes_results`. The client never derives it — the fold is knowledge the
  /// entity already holds.
  Future<String> state({String? asOf}) async {
    final r = await capture('fold', [
      if (asOf != null) ...['--as-of', asOf],
      '--state',
    ]);
    if (r.exitCode != 0) {
      throw StateError('chat: cannot fold $coord — ${r.stderr}'.trim());
    }
    return (r.stdout as String).trim();
  }

  /// The commit the instance stands at, or null if it has not been born.
  ///
  /// **Every screen is pinned to one of these.** The circuit is asynchronous, so
  /// a transcript read at one instant and a state read at the next can describe
  /// a session that never existed — which is how a screen once printed a prompt
  /// with no reply under the word `idle`. One reading, one commit.
  Future<String?> tip() async {
    final r = await Process.run('entity', [..._at, 'tip', '$coord']);
    if (r.exitCode != 0) return null;
    final sha = (r.stdout as String).trim();
    return sha.isEmpty ? null : sha;
  }

  /// The message files in order, at a point in history. Names carry their own
  /// chronology, which is why nothing here has to sort by time.
  Future<List<String>> messageNames({String? asOf}) async {
    final listed = await Process.run('entity', [
      ..._at,
      'ls',
      '$coord:llm/messages',
      if (asOf != null) ...['--as-of', asOf],
    ]);
    if (listed.exitCode != 0) {
      throw StateError(
        'chat: cannot list $coord:llm/messages — ${listed.stderr}'.trim(),
      );
    }
    return (listed.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.endsWith('/.gitkeep'))
        .toList()
      ..sort();
  }

  /// The transcript, read through the ontology and never through Git — the same
  /// road `fold` takes. A `.jsonl` is the assistant's event stream and is folded
  /// by the library that owns folding; a `.json` is one message already.
  Future<List<StoredMessage>> transcript({String? asOf}) async {
    final pin = asOf == null ? const <String>[] : ['--as-of', asOf];
    final names = await messageNames(asOf: asOf);

    final out = <StoredMessage>[];
    for (final name in names) {
      final read =
          await Process.run('entity', [..._at, 'read', '$coord:$name', ...pin]);
      if (read.exitCode != 0) continue;
      final body = read.stdout as String;
      out.add(StoredMessage(name, await _decode(name, body)));
    }
    return out;
  }

  /// Arm one landing of this conversation to one of the entity's functions.
  ///
  /// The client owns no arming of its own — this exists only because `install`
  /// does not read the manifest's `on:` table yet, and `chat new` says so where
  /// it calls it.
  Future<int> arm(String event, String function) async {
    final r = await Process.run('entity', [
      ..._at,
      'on',
      '$coord',
      event,
      '--',
      'entity',
      ..._at,
      'run',
      '$coord',
      function,
    ]);
    if (r.exitCode != 0) stderr.write(r.stderr);
    return r.exitCode;
  }

  /// `entity log` verbatim — the audit lens shows the acts, and the acts are
  /// the primitive's to describe.
  Future<String> log() async {
    final r = await Process.run('entity', [..._at, 'log', '$coord']);
    if (r.exitCode != 0) {
      throw StateError('chat: cannot log $coord — ${r.stderr}'.trim());
    }
    return r.stdout as String;
  }

  static Future<ChatMessage> _decode(String name, String body) async {
    if (!name.endsWith('.jsonl')) return decodeMessageJson(body);
    final events = const LineSplitter()
        .convert(body)
        .where((l) => l.trim().isNotEmpty)
        .map(decodeEventJson);
    return Stream<ChatEvent>.fromIterable(events).foldToMessage();
  }
}
