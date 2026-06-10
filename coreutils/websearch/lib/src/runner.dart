import 'dart:convert';
import 'dart:io';

import 'engine.dart';
import 'result.dart';

/// Runs a search via [engine] and returns parsed results.
///
/// [pathOverride] prepends a directory to PATH before invoking the engine
/// binary — used in tests to inject a stub without touching the real PATH.
///
/// Throws [WebsearchEngineNotFoundError] if the engine binary is not on PATH.
/// Throws [WebsearchQueryError] if the engine exits non-zero or returns no results.
Future<List<SearchResult>> search(
  String query, {
  Engine engine = Engine.ddgr,
  int count = 10,
}) =>
    searchWithPath(query, engine: engine, count: count);

/// Same as [search] with an explicit [pathOverride] prepended to PATH.
Future<List<SearchResult>> searchWithPath(
  String query, {
  Engine engine = Engine.ddgr,
  int count = 10,
  String? pathOverride,
}) async {
  return switch (engine) {
    Engine.ddgr => _runDdgr(query, count: count, pathOverride: pathOverride),
    Engine.googler => throw UnimplementedError(
        'googler is not yet implemented. Install ddgr: brew install ddgr',
      ),
  };
}

Future<List<SearchResult>> _runDdgr(
  String query, {
  required int count,
  String? pathOverride,
}) async {
  const binaryName = 'ddgr';

  // Resolve the binary path respecting pathOverride so tests can stub ddgr.
  // pathOverride replaces PATH entirely (not prepends) so tests that pass an
  // empty dir get a genuine "not found" without the system ddgr leaking in.
  final effectivePath =
      pathOverride ?? Platform.environment['PATH'] ?? '';

  final resolved = _resolveOnPath(binaryName, effectivePath);
  if (resolved == null) throw WebsearchEngineNotFoundError(binaryName);

  final ProcessResult result;
  try {
    result = await Process.run(
      resolved,
      ['--json', '-n', '$count', query],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
      runInShell: false,
    );
  } on ProcessException {
    throw WebsearchEngineNotFoundError(binaryName);
  }

  if (result.exitCode != 0) {
    throw WebsearchQueryError(
      'ddgr exited ${result.exitCode}: ${(result.stderr as String).trim()}',
    );
  }

  final raw = result.stdout as String;
  final List<dynamic> items;
  try {
    items = jsonDecode(raw) as List<dynamic>;
  } catch (_) {
    throw WebsearchQueryError('ddgr returned non-JSON output');
  }

  if (items.isEmpty) throw WebsearchQueryError('ddgr returned no results');

  return items
      .cast<Map<String, dynamic>>()
      .map(SearchResult.fromDdgr)
      .toList();
}

/// Returns the absolute path of [name] found on [pathVar], or null.
String? _resolveOnPath(String name, String pathVar) {
  for (final dir in pathVar.split(':')) {
    if (dir.isEmpty) continue;
    final candidate = File('$dir/$name');
    if (candidate.existsSync()) return candidate.path;
  }
  return null;
}

final class WebsearchEngineNotFoundError extends Error {
  WebsearchEngineNotFoundError(this.binary);
  final String binary;
  @override
  String toString() =>
      'websearch: engine binary "$binary" not found on PATH. '
      'Install it (e.g. brew install ddgr) and retry.';
}

final class WebsearchQueryError extends Error {
  WebsearchQueryError(this.message);
  final String message;
  @override
  String toString() => 'websearch: $message';
}
