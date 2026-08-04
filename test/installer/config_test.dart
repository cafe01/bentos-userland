import 'dart:io';

import 'package:bentos_userland/installer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The compiled-in default stream — the one thing a machine that holds nothing
/// but this binary already knows. It has no file behind it and no flag in front
/// of it: if the address is wrong, `bentos install` on a clean machine reaches
/// for a repository that does not answer, and nothing else in the system says
/// so. Which is why it is asserted rather than trusted.
void main() {
  test('the default stream points at the repo whose name it carries', () {
    final stream = BentosConfig.defaultStreams['bentos-userland'];
    expect(stream, isNotNull);
    expect(stream!.repo, 'cafe01/bentos-userland');
    // One repo is one product, so the tag needs no product prefix — and a
    // prefix that grew one would mean the producer rule was broken upstream.
    expect(stream.tagPrefix, 'v');
    expect(stream.isLocal, isFalse);
  });

  test('a machine with no config file still holds the default', () {
    final root = Directory.systemTemp.createTempSync('bentos-config-');
    addTearDown(() => root.deleteSync(recursive: true));

    // No ~/.bentos, no config.toml — the clean machine the bootstrap lands on.
    final config = BentosConfig.load(environment: const {}, homeDir: root.path);
    expect(config.streams.keys, contains('bentos-userland'));
    expect(config.streams['bentos-userland']!.repo, 'cafe01/bentos-userland');
    expect(config.prefix, p.join(root.path, '.local', 'bin'));
    expect(config.home, p.join(root.path, '.bentos'));
  });

  test('a config file overrides the default without deleting it', () {
    final root = Directory.systemTemp.createTempSync('bentos-config-');
    addTearDown(() => root.deleteSync(recursive: true));
    final home = p.join(root.path, '.bentos');
    Directory(home).createSync(recursive: true);
    File(p.join(home, 'config.toml')).writeAsStringSync('''
prefix = "~/bin"

[streams.bentos-kernel]
repo = "cafe01/bentos-kernel"
tag_prefix = "v"
''');

    final config = BentosConfig.load(environment: {'HOME': root.path}, homeDir: root.path);
    expect(config.prefix, p.join(root.path, 'bin'));
    expect(config.streams['bentos-kernel']!.repo, 'cafe01/bentos-kernel');
    expect(config.streams['bentos-userland']!.repo, 'cafe01/bentos-userland');
  });
}
