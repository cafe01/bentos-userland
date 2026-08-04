import 'dart:convert';
import 'dart:io';

import 'package:bentos_userland/installer.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The installer driven against a local fixture stream: a directory laid out
/// like a release, holding a manifest and its assets. It proves the mechanism —
/// verify, materialize, substitute the binary on the PATH — with no network and
/// no touching of the operator's own `~/.bentos`.
void main() {
  late Directory root;
  late String home;
  late String prefix;
  late String streamDir;
  late HostPlatform host;

  setUp(() {
    root = Directory.systemTemp.createTempSync('bentos-installer-');
    home = p.join(root.path, 'bentos-home');
    prefix = p.join(home, 'bin');
    streamDir = p.join(root.path, 'stream');
    Directory(streamDir).createSync(recursive: true);
    host = const HostPlatform('linux', 'x64');
  });

  tearDown(() => root.deleteSync(recursive: true));

  /// One fixture release: each executable is a shell script that prints its own
  /// name and version, so "installed" can be proven by running the thing.
  String publish(String version, List<String> names, {Map<String, String>? corruptHash}) {
    final artifacts = <Map<String, Object?>>[];
    for (final name in names) {
      final body = '#!/bin/sh\necho "$name $version"\n';
      final asset = '$name-$host';
      File(p.join(streamDir, asset)).writeAsStringSync(body);
      artifacts.add({
        'name': name,
        'platform': '$host',
        'asset': asset,
        'sha256': corruptHash?[name] ?? sha256.convert(utf8.encode(body)).toString(),
        'size': body.length,
      });
    }
    File(p.join(streamDir, 'bentos-release.json')).writeAsStringSync(json.encode({
      'product': 'bentos-userland',
      'version': version,
      'executables': [
        for (final name in names)
          {'name': name, 'entrypoint': 'bin/$name.dart', 'platforms': ['$host']},
      ],
      'artifacts': artifacts,
    }));
    return version;
  }

  BentosRunner runnerWith(StringBuffer out, StringBuffer err) => BentosRunner(
        out: out,
        err: err,
        host: host,
        config: BentosConfig(
          home: home,
          prefix: prefix,
          // Under this test's own root: the runner now looks at the old prefix
          // on every verb, and no gate may look at the operator's `~/.local/bin`.
          legacyPrefix: p.join(root.path, 'legacy-bin'),
          streams: {'bentos-userland': StreamConfig(name: 'bentos-userland', dir: streamDir)},
        ),
      );

  Future<(int, String, String)> run(List<String> args) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final runner = runnerWith(out, err);
    await runner.run(args);
    return (runner.exitCode, out.toString(), err.toString());
  }

  String pathEntry(String name) => p.join(prefix, name);

  test('installs a release: the name on the PATH is the binary itself', () async {
    publish('0.2.0', ['mem', 'place']);

    final (code, out, _) = await run(['install']);
    expect(code, 0);
    expect(out, contains('0.2.0'));
    expect(out, contains('mem'));

    // Substitution, not indirection: what sits on the PATH is a regular file
    // holding the artifact's own bytes, and resolves through nothing.
    expect(FileSystemEntity.typeSync(pathEntry('mem'), followLinks: false),
        FileSystemEntityType.file);
    expect(
      File(pathEntry('mem')).readAsBytesSync(),
      File(p.join(home, 'versions', 'bentos-userland', '0.2.0', 'bin', 'mem')).readAsBytesSync(),
    );

    final ran = Process.runSync(pathEntry('mem'), const []);
    expect(ran.exitCode, 0);
    expect(ran.stdout, contains('mem 0.2.0'));
  });

  test('the pointer lives in state.json, and it carries current and previous', () async {
    publish('0.2.0', ['mem']);
    await run(['install']);
    publish('0.3.0', ['mem']);
    await run(['install']);

    final state = json.decode(File(p.join(home, 'state.json')).readAsStringSync())
        as Map<String, Object?>;
    final stream = (state['streams'] as Map)['bentos-userland'] as Map;
    expect(stream['current'], '0.3.0');
    expect(stream['previous'], '0.2.0');

    // And it carries nothing about content: the names are read from the disk.
    expect(stream.keys, unorderedEquals(['current', 'previous']));
  });

  test('a new version overwrites every name, and rollback writes them back', () async {
    publish('0.2.0', ['mem', 'place']);
    await run(['install']);
    publish('0.3.0', ['mem', 'place']);
    await run(['install']);

    expect(Process.runSync(pathEntry('mem'), const []).stdout, contains('mem 0.3.0'));
    expect(Process.runSync(pathEntry('place'), const []).stdout, contains('place 0.3.0'));

    final (code, out, _) = await run(['rollback']);
    expect(code, 0);
    expect(out, contains('0.2.0'));
    expect(Process.runSync(pathEntry('mem'), const []).stdout, contains('mem 0.2.0'));
    expect(Process.runSync(pathEntry('place'), const []).stdout, contains('place 0.2.0'));

    // Rollback fetched nothing: both versions are still materialized.
    expect(Directory(p.join(home, 'versions', 'bentos-userland', '0.3.0')).existsSync(), isTrue);
  });

  test('an interrupted activation is finished by running the same command again', () async {
    publish('0.2.0', ['mem', 'place']);
    await run(['install']);
    publish('0.3.0', ['mem', 'place']);
    await run(['install']);

    // A run that died between the two renames: one name moved, the pointer did
    // not. The pointer going last is what makes this state legible as "0.2.0
    // with drift" rather than as a version nobody can name.
    final store = VersionStore(home: home, prefix: prefix);
    store.rollback('bentos-userland');
    store.substitute(stream: 'bentos-userland', version: '0.3.0', name: 'mem');

    var (_, out, _) = await run(['list']);
    expect(out, contains('! mem'));

    final (code, _, _) = await run(['install']);
    expect(code, 0);
    expect(Process.runSync(pathEntry('mem'), const []).stdout, contains('mem 0.3.0'));
    expect(Process.runSync(pathEntry('place'), const []).stdout, contains('place 0.3.0'));
    (_, out, _) = await run(['list']);
    expect(out, isNot(contains('!')));
  });

  test('a surgical install carries the rest forward — no name is left behind', () async {
    publish('0.2.0', ['mem', 'place']);
    await run(['install']);
    publish('0.3.0', ['mem', 'place']);

    final (code, _, _) = await run(['install', 'mem']);
    expect(code, 0);
    // mem moved, place did not — and place still runs, from the new version dir.
    expect(Process.runSync(pathEntry('mem'), const []).stdout, contains('mem 0.3.0'));
    expect(Process.runSync(pathEntry('place'), const []).stdout, contains('place 0.2.0'));
  });

  test('a corrupt artifact is refused and nothing reaches the PATH', () async {
    publish('0.2.0', ['mem'], corruptHash: {'mem': 'deadbeef' * 8});

    final (code, _, err) = await run(['install']);
    expect(code, 1);
    expect(err, contains('sha256 mismatch'));
    expect(File(pathEntry('mem')).existsSync(), isFalse);
    expect(File(p.join(home, 'state.json')).existsSync(), isFalse);
  });

  test('a corrupt artifact leaves the version that was already live untouched', () async {
    publish('0.2.0', ['mem']);
    await run(['install']);
    publish('0.3.0', ['mem'], corruptHash: {'mem': 'deadbeef' * 8});

    final (code, _, _) = await run(['install']);
    expect(code, 1);
    expect(Process.runSync(pathEntry('mem'), const []).stdout, contains('mem 0.2.0'));
    expect(VersionStore(home: home, prefix: prefix).currentVersion('bentos-userland'), '0.2.0');
  });

  test('a name with no build for this host is reported, not invented', () async {
    publish('0.2.0', ['mem']);
    // Re-publish declaring an executable no artifact covers.
    final manifest = json.decode(File(p.join(streamDir, 'bentos-release.json')).readAsStringSync())
        as Map<String, Object?>;
    (manifest['executables'] as List).add({'name': 'llm', 'entrypoint': 'bin/llm.dart', 'platforms': ['$host']});
    File(p.join(streamDir, 'bentos-release.json')).writeAsStringSync(json.encode(manifest));

    final (code, _, err) = await run(['install']);
    expect(code, 0);
    expect(err, contains('no linux-x64 build'));
    expect(err, contains('llm'));
    expect(File(pathEntry('llm')).existsSync(), isFalse);
  });

  test('an unknown name refuses before anything is fetched', () async {
    publish('0.2.0', ['mem']);
    final (code, _, err) = await run(['install', 'nope']);
    expect(code, 1);
    expect(err, contains('nope'));
    expect(File(p.join(home, 'state.json')).existsSync(), isFalse);
  });

  test('list says so when nothing is installed', () async {
    final (code, out, _) = await run(['list']);
    expect(code, 0);
    expect(out, contains('not installed'));
  });

  group('drift is a reading of the disk, in both directions', () {
    setUp(() async {
      publish('0.2.0', ['mem', 'place']);
      await run(['install']);
    });

    test('an intact install reports no drift and exits 0', () async {
      final (code, out, _) = await run(['list']);
      expect(code, 0);
      expect(out, contains('· mem'));
      expect(out, contains('· place'));
      expect(out, isNot(contains('drifted')));
    });

    test('a foreign binary at our name is drift — the file changed', () async {
      File(pathEntry('mem')).writeAsStringSync('#!/bin/sh\necho foreign\n');

      final (code, out, _) = await run(['list']);
      expect(code, 2);
      expect(out, contains('! mem'));
      expect(out, contains('drifted'));
      // Disjoint: the name nobody touched is still clean in the same reading.
      expect(out, contains('· place'));
    });

    test('a moved pointer is drift — the file did not change', () async {
      // The other direction, with a disjoint cause: the bytes on the PATH are
      // untouched and the version they are supposed to be has moved under them.
      publish('0.3.0', ['mem', 'place']);
      await run(['install']);
      final intact = File(pathEntry('mem')).readAsBytesSync();
      InstallState.read(home).activate('bentos-userland', '0.2.0');

      final (code, out, _) = await run(['list']);
      expect(code, 2);
      expect(out, contains('! mem'));
      expect(File(pathEntry('mem')).readAsBytesSync(), intact);
    });

    test('a name gone from the PATH is missing, and missing is drift too', () async {
      File(pathEntry('place')).deleteSync();

      final (code, out, _) = await run(['list']);
      expect(code, 2);
      expect(out, contains('? place'));
      expect(out, contains('missing'));
      expect(out, contains('· mem'));
    });

    test('re-installing cures drift', () async {
      File(pathEntry('mem')).writeAsStringSync('#!/bin/sh\necho foreign\n');
      expect((await run(['list'])).$1, 2);

      await run(['install']);
      final (code, out, _) = await run(['list']);
      expect(code, 0);
      expect(out, isNot(contains('drifted')));
    });
  });
}
