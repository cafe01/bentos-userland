import 'dart:io' as io;

/// The `<os>-<arch>` token an artifact is published under.
///
/// The installer's own platform is detected here and nowhere else: every
/// comparison against a manifest's `platform` field goes through this string,
/// so a machine that has no artifact says so once, by name.
final class HostPlatform {
  const HostPlatform(this.os, this.arch);

  final String os;
  final String arch;

  /// The running machine. Injected in tests through [BentosPlatform.host].
  factory HostPlatform.detect() {
    final os = switch (io.Platform.operatingSystem) {
      'linux' => 'linux',
      'macos' => 'macos',
      'windows' => 'windows',
      final other => other,
    };
    return HostPlatform(os, _arch());
  }

  /// Dart exposes no arch directly; the version banner carries it as the last
  /// field of `"… on \"<os>_<arch>\""`.
  static String _arch() {
    final v = io.Platform.version;
    final match = RegExp(r'"[a-z]+_([a-z0-9]+)"').firstMatch(v);
    return switch (match?.group(1)) {
      'x64' => 'x64',
      'arm64' => 'arm64',
      final other => other ?? 'unknown',
    };
  }

  @override
  String toString() => '$os-$arch';
}
