import 'dart:io';

import 'package:bentos_userland/installer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fixture_binary.dart';

void main() {
  late Directory root;
  late String home;
  late String prefix;

  const stream = 'bentos-userland';

  setUp(() {
    root = Directory.systemTemp.createTempSync('bentos-shadows-');
    home = p.join(root.path, 'bentos-home');
    prefix = p.join(home, 'bin');
  });

  tearDown(() => root.deleteSync(recursive: true));

  String exeName(String name) => Platform.isWindows ? '$name.exe' : name;

  final pathSep = Platform.isWindows ? ';' : ':';

  String pathEntry(String name) => p.join(prefix, exeName(name));

  String script(String text) => '#!/bin/sh\n$text\n';

  void hold(String version, Map<String, String> bodies) {
    final dir = Directory(p.join(home, 'versions', stream, version, 'bin'))
      ..createSync(recursive: true);
    for (final entry in bodies.entries) {
      final file = File(p.join(dir.path, entry.key))
        ..writeAsBytesSync(FixtureBinaries.bytesFor(entry.value));
      Process.runSync('chmod', ['+x', file.path]);
    }
  }

  group('shadow on the PATH', () {
    test('a name answered earlier by something else lights up', () {
      hold('0.2.0', {'mem': 'mem 0.2.0'});
      final store = VersionStore(home: home, prefix: prefix);
      store.activate(stream, '0.2.0');

      final ahead = p.join(root.path, 'ahead');
      Directory(ahead).createSync();
      File(p.join(ahead, exeName('mem'))).writeAsStringSync(script('echo "someone else"'));

      final shadows = PathShadows(prefix: prefix, pathDirs: [ahead, prefix]);
      final finding = shadows.ahead('mem',
          ourArtifact: store.artifactPath(stream, '0.2.0', 'mem'));

      expect(finding, isNotNull);
      expect(finding!.path, p.join(ahead, exeName('mem')));
      expect(finding.isOurs, isFalse);
      expect(shadows.prefixIsUnreachable, isFalse);
    });

    test('no shadow, no word', () {
      hold('0.2.0', {'mem': 'mem 0.2.0'});
      final store = VersionStore(home: home, prefix: prefix);
      store.activate(stream, '0.2.0');

      final behind = p.join(root.path, 'behind');
      Directory(behind).createSync();
      File(p.join(behind, exeName('mem'))).writeAsStringSync(script('echo "later"'));

      final shadows = PathShadows(prefix: prefix, pathDirs: [prefix, behind]);
      expect(
          shadows.ahead('mem',
              ourArtifact: store.artifactPath(stream, '0.2.0', 'mem')),
          isNull);
    });

    test('our own bytes ahead of us are ours, not a stranger', () {
      hold('0.2.0', {'mem': 'mem 0.2.0'});
      final store = VersionStore(home: home, prefix: prefix);
      store.activate(stream, '0.2.0');

      final ahead = p.join(root.path, 'ahead');
      Directory(ahead).createSync();
      Link(p.join(ahead, exeName('mem'))).createSync(pathEntry('mem'));

      final finding = PathShadows(prefix: prefix, pathDirs: [ahead, prefix])
          .ahead('mem', ourArtifact: store.artifactPath(stream, '0.2.0', 'mem'));

      expect(finding, isNotNull);
      expect(finding!.isOurs, isTrue);
    });

    test('a prefix that is on nobody\'s PATH is unreachable, and says so', () {
      expect(
        PathShadows(prefix: prefix, pathDirs: ['/usr/bin', '/bin'])
            .prefixIsUnreachable,
        isTrue,
      );
    });

    test('under Windows semantics the shadow is found by its .exe name', () {
      hold('0.2.0', {'mem': 'mem 0.2.0'});
      final store = VersionStore(home: home, prefix: prefix, windowsSemantics: true);
      store.activate(stream, '0.2.0');

      final ahead = p.join(root.path, 'ahead');
      Directory(ahead).createSync();
      File(p.join(ahead, 'mem.exe')).writeAsStringSync(script('echo "someone else"'));

      final shadows = PathShadows(
        prefix: prefix,
        pathDirs: [ahead, prefix],
        windowsSemantics: true,
      );
      final finding = shadows.ahead('mem',
          ourArtifact: store.artifactPath(stream, '0.2.0', 'mem'));

      expect(finding, isNotNull);
      expect(finding!.path, p.join(ahead, 'mem.exe'));
    });
  });

  group('through the command', () {
    BentosRunner runner(StringBuffer out, StringBuffer err, {String? path}) =>
        BentosRunner(
          out: out,
          err: err,
          host: const HostPlatform('linux', 'x64'),
          environment: {if (path != null) 'PATH': path},
          config: BentosConfig(
            home: home,
            prefix: prefix,
            streams: const {'bentos-userland': StreamConfig(name: 'bentos-userland')},
          ),
        );

    test('`list` says out loud when something answers our name first', () async {
      hold('0.1.0', {'mem': 'mem 0.1.0'});
      final store = VersionStore(home: home, prefix: prefix);
      store.activate(stream, '0.1.0');
      store.substitute(stream: stream, version: '0.1.0', name: 'mem');

      final ahead = p.join(root.path, 'ahead');
      Directory(ahead).createSync();
      File(p.join(ahead, exeName('mem'))).writeAsStringSync(script('echo "someone else"'));

      final out = StringBuffer();
      final err = StringBuffer();
      await runner(out, err, path: [ahead, prefix].join(pathSep)).run(['list']);

      expect(out.toString(), contains('shadowed'));
      expect(out.toString(), contains(p.join(ahead, exeName('mem'))));
    });

    test('and stays quiet when nothing does', () async {
      hold('0.1.0', {'mem': 'mem 0.1.0'});
      final store = VersionStore(home: home, prefix: prefix);
      store.activate(stream, '0.1.0');
      store.substitute(stream: stream, version: '0.1.0', name: 'mem');

      final out = StringBuffer();
      final err = StringBuffer();
      await runner(out, err, path: [prefix, '/usr/bin'].join(pathSep)).run(['list']);

      expect(out.toString(), isNot(contains('shadowed')));
      expect(out.toString(), isNot(contains('not on your PATH')));
    });

    test('a prefix nobody can reach is said plainly', () async {
      hold('0.1.0', {'mem': 'mem 0.1.0'});
      final store = VersionStore(home: home, prefix: prefix);
      store.activate(stream, '0.1.0');
      store.substitute(stream: stream, version: '0.1.0', name: 'mem');

      final out = StringBuffer();
      final err = StringBuffer();
      await runner(out, err, path: ['/usr/bin', '/bin'].join(pathSep)).run(['list']);

      expect(out.toString(), contains('is not on your PATH'));
    });
  });
}
