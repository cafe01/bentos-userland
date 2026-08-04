import 'dart:convert';

/// `bentos-release.json` — the declared registry of what a producing repo
/// makes, and the one contract shared by CI and the installer.
///
/// The source form declares [executables]; CI enriches the same document with
/// [artifacts] — one entry per executable per platform, each carrying the
/// asset name and the hash — and republishes it as an asset of the release.
/// The installer only ever reads the enriched form: an entry with no artifacts
/// is a release nothing can be fetched from.
final class ReleaseManifest {
  const ReleaseManifest({
    required this.product,
    required this.version,
    required this.executables,
    required this.artifacts,
  });

  final String product;
  final String version;
  final List<ExecutableSpec> executables;
  final List<ArtifactSpec> artifacts;

  static ReleaseManifest parse(String source) {
    final Object? decoded = json.decode(source);
    if (decoded is! Map<String, Object?>) {
      throw ManifestFormatException('manifest is not a JSON object');
    }
    final product = decoded['product'];
    final version = decoded['version'];
    if (product is! String || product.isEmpty) {
      throw ManifestFormatException('manifest has no "product"');
    }
    if (version is! String || version.isEmpty) {
      throw ManifestFormatException('manifest has no "version"');
    }
    return ReleaseManifest(
      product: product,
      version: version,
      executables: _list(decoded['executables'], ExecutableSpec._parse),
      artifacts: _list(decoded['artifacts'], ArtifactSpec._parse),
    );
  }

  static List<T> _list<T>(Object? raw, T Function(Map<String, Object?>) parse) {
    if (raw == null) return const [];
    if (raw is! List) throw ManifestFormatException('expected a list');
    return [
      for (final entry in raw)
        if (entry is Map<String, Object?>)
          parse(entry)
        else
          throw ManifestFormatException('list entry is not an object'),
    ];
  }

  /// Every executable name the release declares, in declaration order.
  List<String> get names => [for (final e in executables) e.name];

  /// The artifact for [name] on [platform], or null when the release carries
  /// no build of it — which is a fact about the release, not an error here.
  ArtifactSpec? artifactFor(String name, String platform) {
    for (final a in artifacts) {
      if (a.name == name && a.platform == platform) return a;
    }
    return null;
  }
}

final class ExecutableSpec {
  const ExecutableSpec({
    required this.name,
    required this.entrypoint,
    required this.platforms,
  });

  final String name;
  final String entrypoint;
  final List<String> platforms;

  static ExecutableSpec _parse(Map<String, Object?> raw) {
    final name = raw['name'];
    if (name is! String || name.isEmpty) {
      throw ManifestFormatException('executable has no "name"');
    }
    return ExecutableSpec(
      name: name,
      entrypoint: raw['entrypoint'] as String? ?? '',
      platforms: [
        for (final p in (raw['platforms'] as List? ?? const [])) '$p',
      ],
    );
  }
}

final class ArtifactSpec {
  const ArtifactSpec({
    required this.name,
    required this.platform,
    required this.asset,
    required this.sha256,
    this.size,
  });

  final String name;
  final String platform;
  final String asset;
  final String sha256;
  final int? size;

  static ArtifactSpec _parse(Map<String, Object?> raw) {
    final name = raw['name'];
    final platform = raw['platform'];
    final asset = raw['asset'];
    final sha256 = raw['sha256'];
    if (name is! String || platform is! String || asset is! String) {
      throw ManifestFormatException(
        'artifact needs "name", "platform" and "asset"',
      );
    }
    if (sha256 is! String || sha256.isEmpty) {
      throw ManifestFormatException('artifact "$name" has no "sha256"');
    }
    return ArtifactSpec(
      name: name,
      platform: platform,
      asset: asset,
      sha256: sha256.toLowerCase(),
      size: raw['size'] as int?,
    );
  }
}

final class ManifestFormatException implements Exception {
  ManifestFormatException(this.message);
  final String message;
  @override
  String toString() => 'bad manifest: $message';
}
