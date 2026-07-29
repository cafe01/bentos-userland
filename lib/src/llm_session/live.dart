/// The live seam the log does not carry: a turn in flight, published per
/// session and persisted nowhere.
///
/// A person watches the answer form token by token while the log carries only
/// the finished turn, so the live bytes travel a path of their own — a unix
/// socket in the entity's arming dir, best-effort by design. A face that misses
/// them loses the animation and nothing else, the committed `reply` being the
/// only truth; and nothing in flight is ever written into the worktree, which
/// would make the tree lie about the session.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chat_inference/chat_inference.dart';
import 'package:path/path.dart' as p;

import '../entity/git_entity.dart';

/// The rendezvous point of one session's live seam.
///
/// It lives in the runtime dir rather than in the entity, for a reason the OS
/// imposes: a unix socket path is capped near 104 bytes, and a session may sit
/// anywhere. So the name is derived from the entity's canonical path — both
/// ends compute the same one — and what it names is transient by nature, which
/// is exactly what a runtime dir is for.
String _socketPath(GitEntity entity) {
  final dir = Directory(p.join(Directory.systemTemp.path, 'bentos-live'));
  dir.createSync(recursive: true);
  return p.join(dir.path, '${_fingerprint(_canonical(entity))}.sock');
}

String _canonical(GitEntity entity) {
  try {
    return entity.dir.resolveSymbolicLinksSync();
  } on FileSystemException {
    return entity.dir.absolute.path;
  }
}

/// FNV-1a, 64-bit — a stable name for a path, computed identically by a face
/// and by a body that never met.
String _fingerprint(String s) {
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);
  final mask = (BigInt.one << 64) - BigInt.one;
  final prime = BigInt.parse('100000001b3', radix: 16);
  for (final byte in utf8.encode(s)) {
    hash = (hash ^ BigInt.from(byte)) * prime & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

InternetAddress _address(GitEntity entity) =>
    InternetAddress(_socketPath(entity), type: InternetAddressType.unix);

/// The publishing end — the runner's. Opening it costs nothing when nobody is
/// listening, and publishing to nobody is not an error.
final class LiveTurn {
  LiveTurn._(this._socket);

  final Socket? _socket;

  /// Connects if a listener is there; yields a sink that discards otherwise.
  static Future<LiveTurn> open(GitEntity entity) async {
    if (!File(_socketPath(entity)).existsSync()) return LiveTurn._(null);
    try {
      return LiveTurn._(await Socket.connect(_address(entity), 0));
    } on SocketException {
      // A stale socket file, or a listener that left between the two lines.
      return LiveTurn._(null);
    }
  }

  void publish(ChatEvent event) {
    try {
      _socket?.write('${encodeEventJson(event)}\n');
    } on SocketException {
      // The listener left mid-turn; the turn is unaffected.
    }
  }

  Future<void> close() async {
    final socket = _socket;
    if (socket == null) return;
    try {
      await socket.flush();
      await socket.close();
    } on SocketException {
      // Already gone.
    }
    socket.destroy();
  }
}

/// The listening end — a face's. Binding it is what makes the seam exist;
/// before that, a runner publishes into nothing.
final class LiveWatch {
  LiveWatch._(this._server, this.events);

  final ServerSocket _server;

  /// Every event published by every body that runs while this watch is open.
  final Stream<ChatEvent> events;

  static Future<LiveWatch> bind(GitEntity entity) async {
    final path = _socketPath(entity);
    final stale = File(path);
    if (stale.existsSync()) stale.deleteSync();

    final server = await ServerSocket.bind(_address(entity), 0);
    final controller = StreamController<ChatEvent>.broadcast();
    server.listen((socket) {
      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isEmpty) return;
        controller.add(decodeEventJson(line));
      });
    });
    return LiveWatch._(server, controller.stream);
  }

  Future<void> close() async {
    await _server.close();
    final stale = File(_server.address.address);
    if (stale.existsSync()) stale.deleteSync();
  }
}
