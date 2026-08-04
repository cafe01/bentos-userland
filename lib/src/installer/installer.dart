import 'package:http/http.dart' as http;

import 'config.dart';
import 'platform.dart';
import 'source.dart';
import 'store.dart';

/// The installation of one release, told about the machine the caller will run
/// — never about the version store behind it.
///
/// The three words are disjoint and are decided by what happened to the bytes
/// in the prefix: [installed] was fetched and put there, [restored] was already
/// held and had to be written again because what sat at that name was not it,
/// [unchanged] is the name nothing happened to. A report that classified by
/// what the store holds would call a machine it had just cured untouched, and
/// the person who ran the command to fix drift would have no word for it.
final class InstallReport {
  InstallReport({
    required this.stream,
    required this.version,
    required this.installed,
    required this.restored,
    required this.unchanged,
    required this.unavailable,
    required this.linked,
  });

  final String stream;
  final String version;

  /// Fetched from the release and written into the prefix.
  final List<String> installed;

  /// Already materialized, and written into the prefix because the file there
  /// had drifted from it — drift cured, which is news of its own.
  final List<String> restored;

  /// The prefix already held exactly this artifact; nothing was written.
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

    final fetched = <String>[];
    final unavailable = <String>[];

    for (final name in wanted) {
      final artifact = manifest.artifactFor(name, '$host');
      if (artifact == null) {
        unavailable.add(name);
        continue;
      }
      if (store.holds(stream, manifest.version, name, artifact.sha256)) {
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
      fetched.add(name);
    }

    // Nothing reaches the prefix until every artifact of this pass is on disk:
    // a failure above leaves the previous version live and untouched.
    final linked = store.namesIn(stream, manifest.version);

    // The classification is read off what activation actually did to the
    // prefix, which is the only source that knows the difference between a name
    // nothing happened to and a name whose drift was just cured.
    final changed = store.activate(stream, manifest.version);

    return InstallReport(
      stream: stream,
      version: manifest.version,
      installed: [for (final n in linked) if (fetched.contains(n)) n],
      restored: [
        for (final n in linked)
          if (!fetched.contains(n) && changed.contains(n)) n,
      ],
      unchanged: [
        for (final n in linked)
          if (!fetched.contains(n) && !changed.contains(n)) n,
      ],
      unavailable: unavailable,
      linked: linked,
    );
  }
}
