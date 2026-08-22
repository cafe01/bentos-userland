import 'dart:convert';
import 'dart:io' as io;

import 'package:path/path.dart' as p;

/// `~/.bentos/state.json` — which version of each stream is live, and which one
/// it replaced.
///
/// The disk stays the truth about *content*: what a version holds is read from
/// its own directory, and what is on the PATH is read by hashing the file that
/// is on the PATH. This file only says which version those readings are supposed
/// to agree with — so a disagreement between the pointer and the disk is drift,
/// which the installer reports, and never a fact one of them silently wins.
final class InstallState {
  InstallState({required this.path, Map<String, StreamState>? streams})
      : _streams = {...?streams};

  final String path;
  final Map<String, StreamState> _streams;

  static InstallState read(String home) {
    final path = p.join(home, 'state.json');
    final file = io.File(path);
    if (!file.existsSync()) return InstallState(path: path);
    final Object? decoded = json.decode(file.readAsStringSync());
    if (decoded is! Map<String, Object?>) return InstallState(path: path);
    final streams = decoded['streams'];
    return InstallState(
      path: path,
      streams: {
        if (streams is Map)
          for (final entry in streams.entries)
            if (entry.value is Map<String, Object?>)
              '${entry.key}': StreamState(
                current: (entry.value as Map<String, Object?>)['current'] as String?,
                previous: (entry.value as Map<String, Object?>)['previous'] as String?,
              ),
      },
    );
  }

  StreamState? operator [](String stream) => _streams[stream];

  /// Record [version] as live, remembering what it replaced. Written through a
  /// staged file inside the same directory, so a pointer is never half-written.
  void activate(String stream, String version) {
    final live = _streams[stream]?.current;
    _streams[stream] = StreamState(
      current: version,
      previous: live == version ? _streams[stream]?.previous : live,
    );
    _write();
  }

  /// Trade current and previous. Returns the version now live, or null when
  /// there is nothing to go back to.
  String? rollback(String stream) {
    final state = _streams[stream];
    final back = state?.previous;
    if (state == null || back == null) return null;
    _streams[stream] = StreamState(current: back, previous: state.current);
    _write();
    return back;
  }

  void _write() {
    io.Directory(p.dirname(path)).createSync(recursive: true);
    final staged = io.File('$path.incoming');
    staged.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({
            'streams': {
              for (final entry in _streams.entries)
                entry.key: {
                  'current': entry.value.current,
                  if (entry.value.previous != null) 'previous': entry.value.previous,
                },
            },
          })}\n',
      flush: true,
    );
    staged.renameSync(path);
  }
}

final class StreamState {
  const StreamState({this.current, this.previous});

  final String? current;
  final String? previous;
}
