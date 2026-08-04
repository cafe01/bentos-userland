import 'package:http/http.dart' as http;

import 'config.dart';
import 'platform.dart';
import 'source.dart';
import 'store.dart';

/// The installation of one release: what was fetched, what was already held,
/// and the version now live.
final class InstallReport {
  InstallReport({
    required this.stream,
    required this.version,
    required this.installed,
    required this.unchanged,
    required this.unavailable,
    required this.linked,
  });

  final String stream;
  final String version;
  final List<String> installed;
  final List<String> unchanged;

  /// Names the release declares but publishes no artifact of for this host.
  final List<String> unavailable;
  final List<String> linked;
}

/// `bentos`'s one act: read a stream's manifest, fetch what the host needs,
/// verify it, and write it over the name on the PATH. Everything the commands
/// do is this with a different set of names.
final class Installer {
  Installer({
    required this.config,
    required this.store,
    HostPlatform? host,
    http.Client? client,
    Map<String, String>? environment,
  })  : host = host ?? HostPlatform.detect(),
        _client = client,
        _environment = environment;

  final BentosConfig config;
  final VersionStore store;
  final HostPlatform host;
  final http.Client? _client;
  final Map<String, String>? _environment;

  ReleaseSource sourceFor(String stream) {
    final declared = config.stream(stream);
    if (declared == null) {
      throw SourceException('no such stream: "$stream"');
    }
    return ReleaseSource.of(declared, client: _client, environment: _environment);
  }

  /// Install [names] from [stream], or the whole release when [names] is empty.
  Future<InstallReport> install({
    required String stream,
    Iterable<String> names = const [],
    ReleaseSource? from,
  }) async {
    final source = from ?? sourceFor(stream);
    final manifest = await source.manifest();
    final wanted = names.isEmpty ? manifest.names : names.toList();

    final unknown = wanted.where((n) => !manifest.names.contains(n)).toList();
    if (unknown.isNotEmpty) {
      throw SourceException(
        'release ${manifest.version} of "$stream" declares no ${unknown.join(", ")} '
        '(it has: ${manifest.names.join(", ")})',
      );
    }

    final installed = <String>[];
    final unchanged = <String>[];
    final unavailable = <String>[];

    for (final name in wanted) {
      final artifact = manifest.artifactFor(name, '$host');
      if (artifact == null) {
        unavailable.add(name);
        continue;
      }
      if (store.holds(stream, manifest.version, name, artifact.sha256)) {
        unchanged.add(name);
        continue;
      }
      final bytes = await source.asset(artifact.asset);
      store.materialize(
        stream: stream,
        version: manifest.version,
        name: name,
        bytes: bytes,
        expectedSha256: artifact.sha256,
      );
      installed.add(name);
    }

    // Nothing reaches the PATH until every artifact of this pass is on disk: a
    // failure above leaves the previous version live and untouched.
    final linked = store.namesIn(stream, manifest.version);
    store.activate(stream, manifest.version);

    return InstallReport(
      stream: stream,
      version: manifest.version,
      installed: installed,
      unchanged: unchanged,
      unavailable: unavailable,
      linked: linked,
    );
  }
}
