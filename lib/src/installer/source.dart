import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'config.dart';
import 'manifest.dart';

/// Where a release is read from. Two forms, one interface: the installer's
/// mechanism — verify, materialize, swap the link — never learns which it is
/// talking to, which is what lets the fixture prove the machinery and the
/// GitHub release prove distribution.
abstract interface class ReleaseSource {
  /// The stream this source serves.
  String get stream;

  /// The enriched `bentos-release.json` of the release being installed.
  Future<ReleaseManifest> manifest();

  /// The bytes of one published asset.
  Future<Uint8List> asset(String name);

  static ReleaseSource of(StreamConfig config, {http.Client? client, Map<String, String>? environment}) =>
      config.isLocal
          ? LocalReleaseSource(config.name, config.dir!)
          : GithubReleaseSource(
              config.name,
              config.repo ?? (throw SourceException('stream "${config.name}" declares neither repo nor dir')),
              tagPrefix: config.tagPrefix,
              client: client,
              environment: environment,
            );
}

/// A directory laid out like a release: the manifest beside its assets.
final class LocalReleaseSource implements ReleaseSource {
  LocalReleaseSource(this.stream, this.dir);

  @override
  final String stream;
  final String dir;

  static const manifestName = 'bentos-release.json';

  @override
  Future<ReleaseManifest> manifest() async {
    final file = io.File(p.join(dir, manifestName));
    if (!file.existsSync()) {
      throw SourceException('stream "$stream": no $manifestName under $dir');
    }
    return ReleaseManifest.parse(await file.readAsString());
  }

  @override
  Future<Uint8List> asset(String name) async {
    final file = io.File(p.join(dir, name));
    if (!file.existsSync()) {
      throw SourceException('stream "$stream": no asset "$name" under $dir');
    }
    return file.readAsBytes();
  }
}

/// GitHub Releases as the registry.
///
/// Everything rides the REST API rather than the browser download URL, because
/// that is the one path that serves a private asset with a token *and* a public
/// asset without one — so the flip to public changes no code here.
///
/// **A release is found by tag prefix, never by `latest`.** One repository
/// publishes several products — the campus carries the userland and the kernel
/// — and `latest` answers *what was released here most recently*, which is the
/// neighbour's product the day the neighbour ships. The stream is the prefix,
/// `userland-v`, and the newest release carrying it is the one this stream
/// means.
final class GithubReleaseSource implements ReleaseSource {
  GithubReleaseSource(
    this.stream,
    this.repo, {
    this.tagPrefix,
    http.Client? client,
    Map<String, String>? environment,
    String? Function()? keyringToken,
    this.tag,
  })  : _client = client ?? http.Client(),
        _env = environment ?? io.Platform.environment,
        _keyringToken = keyringToken ?? _ghAuthToken;

  @override
  final String stream;

  /// `owner/name`.
  final String repo;

  /// The product's tag prefix within a repo that carries several.
  final String? tagPrefix;

  /// One exact release, overriding the prefix search.
  final String? tag;

  final http.Client _client;
  final Map<String, String> _env;
  final String? Function() _keyringToken;

  static const api = 'https://api.github.com';

  Map<String, Object?>? _release;

  @override
  Future<ReleaseManifest> manifest() async =>
      ReleaseManifest.parse(utf8.decode(await asset(LocalReleaseSource.manifestName)));

  @override
  Future<Uint8List> asset(String name) async {
    final release = await _fetchRelease();
    final assets = (release['assets'] as List? ?? const []).cast<Map<String, Object?>>();
    final match = assets.where((a) => a['name'] == name).firstOrNull;
    if (match == null) {
      throw SourceException(
        'stream "$stream": release ${release['tag_name']} of $repo publishes no asset "$name"',
      );
    }
    final response = await _get(
      '$api/repos/$repo/releases/assets/${match['id']}',
      accept: 'application/octet-stream',
    );
    return Uint8List.fromList(response.bodyBytes);
  }

  Future<Map<String, Object?>> _fetchRelease() async {
    final cached = _release;
    if (cached != null) return cached;
    final named = tag;
    if (named != null) {
      final response = await _get(
        '$api/repos/$repo/releases/tags/$named',
        accept: 'application/vnd.github+json',
      );
      return _release = _asRelease(json.decode(response.body));
    }

    final response = await _get(
      '$api/repos/$repo/releases?per_page=100',
      accept: 'application/vnd.github+json',
    );
    final decoded = json.decode(response.body);
    if (decoded is! List) {
      throw SourceException('stream "$stream": unreadable release list from $repo');
    }
    final prefix = tagPrefix ?? '';
    // The API answers newest first, so the first tag carrying this stream's
    // prefix is this stream's current release — and a release of another
    // product in the same repo is simply not a candidate.
    for (final entry in decoded) {
      if (entry is! Map<String, Object?>) continue;
      if (entry['draft'] == true) continue;
      final tagName = entry['tag_name'];
      if (tagName is String && tagName.startsWith(prefix)) {
        return _release = entry;
      }
    }
    throw SourceException(
      'stream "$stream": $repo publishes no release tagged "$prefix…"',
    );
  }

  Map<String, Object?> _asRelease(Object? decoded) => decoded is Map<String, Object?>
      ? decoded
      : throw SourceException('stream "$stream": unreadable release document from $repo');

  Future<http.Response> _get(String url, {required String accept}) async {
    final token = _token();
    final response = await _client.get(
      Uri.parse(url),
      headers: {
        'Accept': accept,
        'X-GitHub-Api-Version': '2022-11-28',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode == 404) {
      throw SourceException(
        token == null
            ? 'stream "$stream": $repo not found — it is private and no token was offered (set GH_TOKEN or run `gh auth login`)'
            : 'stream "$stream": not found in $repo — no release published yet?',
      );
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw SourceException('stream "$stream": $repo refused the token (${response.statusCode})');
    }
    if (response.statusCode >= 300) {
      throw SourceException('stream "$stream": $repo answered ${response.statusCode}');
    }
    return response;
  }

  /// The token is optional by design: a private repo needs one, a public repo
  /// needs none, and the same call serves both. The environment wins over the
  /// `gh` keyring so CI never shells out — and the keyring lookup is injected
  /// so a test of the tokenless path is not silently rescued by the operator's
  /// own logged-in machine.
  String? _token() {
    for (final key in const ['GH_TOKEN', 'GITHUB_TOKEN', 'BENTOS_GITHUB_TOKEN']) {
      final value = _env[key];
      if (value != null && value.isNotEmpty) return value;
    }
    return _keyringToken();
  }

  /// `gh auth token` — present on a developer's machine, absent on the clean
  /// one the bootstrap lands on, and never required.
  static String? _ghAuthToken() {
    try {
      final result = io.Process.runSync('gh', ['auth', 'token']);
      if (result.exitCode == 0) {
        final token = (result.stdout as String).trim();
        if (token.isNotEmpty) return token;
      }
    } on io.ProcessException {
      // no gh on this machine — unauthenticated is a legal path.
    }
    return null;
  }
}

final class SourceException implements Exception {
  SourceException(this.message);
  final String message;
  @override
  String toString() => message;
}
