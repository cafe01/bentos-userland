import 'dart:convert';
import 'dart:io';

import 'package:bentos_userland/installer.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The installer driven against a local fixture stream: a directory laid out
/// like a release, holding a manifest and its assets. It proves the mechanism —
/// verify, materialize, swap the link, put the name on the PATH — with no
/// network and no touching of the operator's own `~/.local/bin`.
void main() {
  late Directory root;
  late String home;
  late String prefix;
  late String streamDir;
  late HostPlatform host;

  setUp(() {
    root = Directory.systemTemp.createTempSync('bentos-installer-');
    home = p.join(root.path, 'bentos-home');
    prefix = p.join(root.path, 'bin');
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

  test('installs a release: the name on the PATH runs, through current', () async {
    publish('0.2.0', ['mem', 'place']);

    final (code, out, _) = await run(['install']);
    expect(code, 0);
    expect(out, contains('0.2.0'));
    expect(out, contains('mem'));

    // The PATH entry is a link, and it resolves through `current` rather than
    // at a version — which is what makes the next activation move it too.
    final link = Link(pathEntry('mem'));
    expect(link.existsSync(), isTrue);
    expect(link.targetSync(), p.join(home, 'versions', 'bentos-userland', 'current', 'bin', 'mem'));

    final ran = Process.runSync(pathEntry('mem'), const []);
    expect(ran.exitCode, 0);
    expect(ran.stdout, contains('mem 0.2.0'));
  });

  test('the swap moves every name at once, and rollback moves them back', () async {
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
  });

  test('activating alone moves the PATH entries — nothing is re-linked', () async {
    publish('0.2.0', ['mem', 'place']);
    await run(['install']);
    publish('0.3.0', ['mem', 'place']);
    await run(['install']);

    // The whole point of linking through `current`: one rename moves every
    // name. Swap the link with no call to link() and the PATH must follow.
    VersionStore(home: home, prefix: prefix).activate('bentos-userland', '0.2.0');
    expect(Process.runSync(pathEntry('mem'), const []).stdout, contains('mem 0.2.0'));
    expect(Process.runSync(pathEntry('place'), const []).stdout, contains('place 0.2.0'));
  });

  test('a surgical install carries the rest forward — no name is left dangling', () async {
    publish('0.2.0', ['mem', 'place']);
    await run(['install']);
    publish('0.3.0', ['mem', 'place']);

    final (code, _, _) = await run(['install', 'mem']);
    expect(code, 0);
    // mem moved, place did not — and place still runs, from the new version dir.
    expect(Process.runSync(pathEntry('mem'), const []).stdout, contains('mem 0.3.0'));
    expect(Process.runSync(pathEntry('place'), const []).stdout, contains('place 0.2.0'));
  });

  test('a corrupt artifact is refused and nothing is linked', () async {
    publish('0.2.0', ['mem'], corruptHash: {'mem': 'deadbeef' * 8});

    final (code, _, err) = await run(['install']);
    expect(code, 1);
    expect(err, contains('sha256 mismatch'));
    expect(File(pathEntry('mem')).existsSync(), isFalse);
    expect(Link(p.join(home, 'versions', 'bentos-userland', 'current')).existsSync(), isFalse);
  });

  test('a corrupt artifact leaves the version that was already live untouched', () async {
    publish('0.2.0', ['mem']);
    await run(['install']);
    publish('0.3.0', ['mem'], corruptHash: {'mem': 'deadbeef' * 8});

    final (code, _, _) = await run(['install']);
    expect(code, 1);
    expect(Process.runSync(pathEntry('mem'), const []).stdout, contains('mem 0.2.0'));
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
    expect(Link(p.join(home, 'versions', 'bentos-userland', 'current')).existsSync(), isFalse);
  });

  test('list reads the disk: version, names and whether the PATH entry is ours', () async {
    publish('0.2.0', ['mem', 'place']);
    await run(['install']);

    var (code, out, _) = await run(['list']);
    expect(code, 0);
    expect(out, contains('0.2.0'));
    expect(out, contains('· mem'));

    // A foreign binary at the same name is not claimed as installed.
    Link(pathEntry('mem')).deleteSync();
    File(pathEntry('mem')).writeAsStringSync('#!/bin/sh\necho foreign\n');
    (code, out, _) = await run(['list']);
    expect(out, contains('! mem'));
    expect(out, contains('not ours'));
  });

  test('list says so when nothing is installed', () async {
    final (code, out, _) = await run(['list']);
    expect(code, 0);
    expect(out, contains('not installed'));
  });
}
