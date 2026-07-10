import 'package:bentos_userland/manifest.dart';
import 'package:test/test.dart';

/// Contract: ManifestRunner routes to BuildCommand by default.
///
/// Routing rules:
///   1. No args           → build (stdin mode, returns without error signal)
///   2. First arg is `-`  → build (stdin alias)
///   3. Unknown first arg → build (treated as FQDN)
///   4. Known subcommand  → that subcommand (no hijack)
void main() {
  group('ManifestRunner — default routing to build', () {
    test('known subcommand "build" is routed explicitly', () async {
      // build with no FQDN reads stdin; we just verify no UsageException is thrown
      // (i.e. "build" is recognized as a command, not hijacked).
      // We can't actually run build in unit tests without stdin, so we test via
      // the runner's command lookup.
      final runner = ManifestRunner();
      expect(runner.commands.containsKey('build'), isTrue);
      expect(runner.commands.containsKey('ls'), isTrue);
      expect(runner.commands.containsKey('new'), isTrue);
    });

    test('normalizeArgs: no args → ["build"]', () {
      expect(ManifestRunner.normalizeArgs([]), ['build']);
    });

    test('normalizeArgs: "-" alone → ["build", "-"]', () {
      expect(ManifestRunner.normalizeArgs(['-']), ['build', '-']);
    });

    test('normalizeArgs: FQDN → ["build", fqdn]', () {
      expect(
        ManifestRunner.normalizeArgs(['alfred.agent']),
        ['build', 'alfred.agent'],
      );
    });

    test('normalizeArgs: unknown first arg with extra args → build prefix', () {
      expect(
        ManifestRunner.normalizeArgs(['john.soul', '--some-flag']),
        ['build', 'john.soul', '--some-flag'],
      );
    });

    test('normalizeArgs: known subcommand "build" is not double-prefixed', () {
      expect(
        ManifestRunner.normalizeArgs(['build', 'alfred.agent']),
        ['build', 'alfred.agent'],
      );
    });

    test('normalizeArgs: known subcommand "ls" is preserved', () {
      expect(ManifestRunner.normalizeArgs(['ls']), ['ls']);
    });

    test('normalizeArgs: known subcommand "new" is preserved', () {
      expect(
        ManifestRunner.normalizeArgs(['new', 'my.atom']),
        ['new', 'my.atom'],
      );
    });

    test('normalizeArgs: --help flag alone is NOT hijacked', () {
      expect(ManifestRunner.normalizeArgs(['--help']), ['--help']);
    });

    test('normalizeArgs: --version flag alone is NOT hijacked', () {
      expect(ManifestRunner.normalizeArgs(['--version']), ['--version']);
    });
  });
}
