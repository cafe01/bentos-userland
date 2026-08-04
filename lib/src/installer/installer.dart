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
    this.replaced,
    this.preexisting = const {},
  });

  final String stream;
  final String version;

  /// The version that was live when this act began, when it was another one.
  ///
  /// It is what tells the two disjoint causes of [restored] apart: bytes
  /// rewritten because the machine moved to another version, and bytes
  /// rewritten because what sat at that name had drifted from the version that
  /// was already live. Null when nothing moved — the target was already the
  /// live one, or there was no live one at all.
  final String? replaced;

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

  /// The names the prefix already held when this act began.
  final Set<String> preexisting;

  /// Whether this act rewrote a `bentos` the caller already had. The next one
  /// they type is then a different binary, which nothing else on the terminal
  /// would say — but a first install replaces nothing, and saying so there
  /// would be the same class of untruth one word smaller.
  bool replacedSelf(String selfName) =>
      preexisting.contains(selfName) &&
      (installed.contains(selfName) || restored.contains(selfName));

  /// One command, one report. `update` installs twice — itself, then the set —
  /// and two boxes for one act read as a contradiction the moment a name is
  /// rewritten by the first pass and found in place by the second: `restored`
  /// above, `unchanged` below, both true of their own pass and neither true of
  /// the command. What the caller asked is what happened to the bytes while
  /// this command ran, so the strongest thing that happened to each name wins.
  InstallReport then(InstallReport next) {
    final installedNames = {...installed, ...next.installed};
    final restoredNames = {...restored, ...next.restored}..removeAll(installedNames);
    final order = [...linked, ...next.linked.where((n) => !linked.contains(n))];
    return InstallReport(
      stream: next.stream,
      version: next.version,
      replaced: replaced ?? next.replaced,
      installed: [for (final n in order) if (installedNames.contains(n)) n],
      restored: [for (final n in order) if (restoredNames.contains(n)) n],
      unchanged: [
        for (final n in order)
          if (!installedNames.contains(n) && !restoredNames.contains(n)) n,
      ],
      unavailable: {...unavailable, ...next.unavailable}.toList(),
      linked: order,
      // The first pass's reading: by the second, a name this command just
      // created is already there, and the machine would look like it had it
      // all along.
      preexisting: preexisting,
    );
  }
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

    // Read before the pointer moves: afterwards there is no way to tell a move
    // between versions from a drift cure, and the two are said differently.
    final live = store.currentVersion(stream);
    final preexisting = store.namesInPrefix(linked);

    // The classification is read off what activation actually did to the
    // prefix, which is the only source that knows the difference between a name
    // nothing happened to and a name whose drift was just cured. Scoped to
    // `wanted` — self-update asking for `bentos` alone must not find the other
    // nine moved on its behalf — intersected with `linked`, since `wanted` may
    // name something this host has no build for at all, and that name was
    // never materialized for `activate` to find.
    final toActivate = linked.where(wanted.contains);
    final changed = store.activate(stream, manifest.version, names: toActivate);

    return InstallReport(
      stream: stream,
      version: manifest.version,
      replaced: live == manifest.version ? null : live,
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
      preexisting: preexisting,
    );
  }

  /// Put a stream's previous version back, and say what it did to the prefix in
  /// the same words an install uses.
  ///
  /// Rollback moves as many binaries as an update does, including the caller's
  /// own — it was reported in one line naming no name, which is the lighter
  /// report for the heavier act. Nothing is fetched, so `installed` is always
  /// empty and every name that moved is `restored`.
  InstallReport? rollback(String stream) {
    final back = store.previousVersion(stream);
    final held = back == null ? const <String>[] : store.namesIn(stream, back);
    final preexisting = store.namesInPrefix(held);
    final outcome = store.rollback(stream);
    if (outcome == null) return null;
    final names = store.namesIn(stream, outcome.version);
    return InstallReport(
      stream: stream,
      version: outcome.version,
      replaced: outcome.from,
      installed: const [],
      restored: [for (final n in names) if (outcome.changed.contains(n)) n],
      unchanged: [for (final n in names) if (!outcome.changed.contains(n)) n],
      unavailable: const [],
      linked: names,
      preexisting: preexisting,
    );
  }
}
