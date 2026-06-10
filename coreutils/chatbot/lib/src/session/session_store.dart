/// Append-only session log — one JSONL file per session.
///
/// Session directory: $XDG_DATA_HOME/chatbot/sessions (fallback ~/.local/share).
/// Each file: `<id>.jsonl` — one proto3-JSON ChatMessage per line, in order.
/// Metadata sidecar: `<id>.meta` — JSON with id, name?, createdAt, turnCount.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bentos_userland/chat.dart';

/// Lightweight session metadata (no messages).
final class SessionMeta {
  final String id;
  final String? name;
  final DateTime createdAt;
  final int turnCount;

  const SessionMeta({
    required this.id,
    this.name,
    required this.createdAt,
    required this.turnCount,
  });

  factory SessionMeta.fromJson(Map<String, dynamic> j) => SessionMeta(
        id: j['id'] as String,
        name: j['name'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
        turnCount: (j['turnCount'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        if (name != null) 'name': name,
        'createdAt': createdAt.toIso8601String(),
        'turnCount': turnCount,
      };

  /// Label shown in `chatbot list` — name if set, otherwise id.
  String get label => name ?? id;
}

final class SessionStore {
  final Directory _dir;

  SessionStore._(this._dir);

  factory SessionStore.open() {
    final base = Platform.environment['XDG_DATA_HOME'] ??
        '${Platform.environment['HOME']}/.local/share';
    final dir = Directory('$base/chatbot/sessions');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return SessionStore._(dir);
  }

  // ---------------------------------------------------------------------------
  // Session lifecycle
  // ---------------------------------------------------------------------------

  /// Creates a new session and returns its ID.
  String create({String? name}) {
    final id = _generateId();
    _writeMeta(SessionMeta(
      id: id,
      name: name,
      createdAt: DateTime.now(),
      turnCount: 0,
    ));
    _logFile(id).writeAsStringSync('');
    return id;
  }

  /// Appends [messages] to the session log and updates turnCount.
  Future<void> append(String id, List<ChatMessage> messages) async {
    final log = _logFile(id);
    final sink = log.openWrite(mode: FileMode.append);
    for (final m in messages) {
      sink.writeln(encodeMessageJson(m));
    }
    await sink.flush();
    await sink.close();
    final meta = _readMeta(id)!;
    _writeMeta(SessionMeta(
      id: meta.id,
      name: meta.name,
      createdAt: meta.createdAt,
      turnCount: meta.turnCount + messages.length,
    ));
  }

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  /// Loads all messages for [idOrName]. Returns null if not found.
  List<ChatMessage>? load(String idOrName) {
    final id = _resolveId(idOrName);
    if (id == null) return null;
    final log = _logFile(id);
    if (!log.existsSync()) return null;
    return log
        .readAsLinesSync()
        .where((l) => l.trim().isNotEmpty)
        .map(decodeMessageJson)
        .toList();
  }

  /// Returns meta for [idOrName], or null if not found.
  SessionMeta? meta(String idOrName) {
    final id = _resolveId(idOrName);
    if (id == null) return null;
    return _readMeta(id);
  }

  /// Returns all sessions sorted by createdAt descending.
  List<SessionMeta> list() {
    final metas = <SessionMeta>[];
    for (final f in _dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.meta')) continue;
      try {
        final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        metas.add(SessionMeta.fromJson(j));
      } catch (_) {}
    }
    metas.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return metas;
  }

  /// Returns the most-recently-created session ID, or null if none.
  String? latestId() {
    final all = list();
    return all.isEmpty ? null : all.first.id;
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// Resolves name → id. If [idOrName] matches an id directly, returns it.
  /// Otherwise looks for a session whose name matches.
  String? _resolveId(String idOrName) {
    if (_metaFile(idOrName).existsSync()) return idOrName;
    for (final m in list()) {
      if (m.name == idOrName) return m.id;
    }
    return null;
  }

  File _logFile(String id) => File('${_dir.path}/$id.jsonl');
  File _metaFile(String id) => File('${_dir.path}/$id.meta');

  SessionMeta? _readMeta(String id) {
    final f = _metaFile(id);
    if (!f.existsSync()) return null;
    return SessionMeta.fromJson(
        jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
  }

  void _writeMeta(SessionMeta m) {
    _metaFile(m.id).writeAsStringSync(jsonEncode(m.toJson()));
  }

  static final _rng = Random.secure();
  static final _chars = 'abcdefghijklmnopqrstuvwxyz0123456789';

  static String _generateId() => String.fromCharCodes(
        Iterable.generate(8, (_) => _chars.codeUnitAt(_rng.nextInt(_chars.length))),
      );
}
