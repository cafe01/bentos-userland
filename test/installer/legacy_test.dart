import 'dart:io';

import 'package:bentos_userland/installer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fixture_binary.dart';

/// The machine that already ran the released installer, met by the one that
/// replaced it.
///
/// Every fixture here is the OLD layout built by hand — links through
/// `current`, no `state.json` — because that is the only shape the assertion
/// can be made against: a store that writes the fixture cannot testify about a
/// store that has to read it.
void main() {
  late Directory root;
  late String home;
  late String prefix;
  late String legacyPrefix;

  const stream = 'bentos-userland';

  setUp(() {
    root = Directory.systemTemp.createTempSync('bentos-legacy-');
    home = p.join(root.path, 'bentos-home');
    prefix = p.join(home, 'bin');
    legacyPrefix = p.join(root.path, 'local-bin');
  });

  tearDown(() => root.deleteSync(recursive: true));

  /// Same law as [VersionStore.prefixName], read here from the real host
  /// because these tests run [layoutOf] and [PathShadows] with no semantics
  /// injected, exactly as the shipped binary does.
  String exeName(String name) => Platform.isWindows ? '$name.exe' : name;

  final pathSep = Platform.isWindows ? ';' : ':';

  /// The name as it actually sits in the new prefix.
  String pathEntry(String name) => p.join(prefix, exeName(name));

  String script(String text) => '#!/bin/sh\n$text\n';

  /// A materialized version, each name a real compiled binary that prints
  /// [bodies]'s value when run — the shim built on top of it is later
  /// executed for real, so it needs a witness the OS can actually run.
  void hold(String version, Map<String, String> bodies) {
    final dir = Directory(p.join(home, 'versions', stream, version, 'bin'))
      ..createSync(recursive: true);
    for (final entry in bodies.entries) {
      final file = File(p.join(dir.path, entry.key))
        ..writeAsBytesSync(FixtureBinaries.bytesFor(entry.value));
      Process.runSync('chmod', ['+x', file.path]);
    }
  }

  /// The released layout, exactly as the version before substitution left it:
  /// `current` and `previous` as links, and the PATH entries pointing *through*
  /// `current` rather than at any version.
  void mountOldLayout({required String current, String? previous}) {
    final streamDir = p.join(home, 'versions', stream);
    Link(p.join(streamDir, 'current')).createSync(p.join(streamDir, current));
    if (previous != null) {
      Link(p.join(streamDir, 'previous')).createSync(p.join(streamDir, previous));
    }
    Directory(legacyPrefix).createSync(recursive: true);
    for (final name in Directory(p.join(streamDir, current, 'bin'))
        .listSync()
        .map((e) => p.basename(e.path))) {
      Link(p.join(legacyPrefix, name))
          .createSync(p.join(streamDir, 'current', 'bin', name));
    }
  }

  LegacyLayout layoutOf() => LegacyLayout(
        home: home,
        legacyPrefix: legacyPrefix,
        store: VersionStore(home: home, prefix: prefix),
      );

  group('adoption', () {
    test('a machine on the old layout is brought into the store', () {
      hold('0.1.0', {'mem': 'mem 0.1.0', 'place': 'place'});
      hold('0.0.9', {'mem': 'mem 0.0.9'});
      mountOldLayout(current: '0.1.0', previous: '0.0.9');

      final reports = layoutOf().adopt(const [stream]);

      expect(reports, hasLength(1));
      expect(reports.single.version, '0.1.0');
      expect(reports.single.previous, '0.0.9');

      // The names on the PATH are binaries now, not links through anything.
      final store = VersionStore(home: home, prefix: prefix);
      expect(store.currentVersion(stream), '0.1.0');
      expect(store.previousVersion(stream), '0.0.9',
          reason: 'both ends of the old pointer are adopted, so rollback survives');
      for (final name in ['mem', 'place']) {
        final onPath = pathEntry(name);
        expect(FileSystemEntity.typeSync(onPath, followLinks: false),
            FileSystemEntityType.file,
            reason: '$name on the new prefix must be the binary itself');
      }
      expect(Process.runSync(pathEntry('mem'), const []).stdout,
          contains('mem 0.1.0'));

      // The dead mechanism's pointer is gone.
      expect(
          FileSystemEntity.typeSync(p.join(home, 'versions', stream, 'current'),
              followLinks: false),
          FileSystemEntityType.notFound);
      expect(
          FileSystemEntity.typeSync(p.join(home, 'versions', stream, 'previous'),
              followLinks: false),
          FileSystemEntityType.notFound);
    });

    test('the old prefix keeps working — every name forwards to the real binary', () {
      // The half that decides whether a live machine breaks. The person's PATH
      // names the old prefix and nothing we do can change that, so the names
      // there have to keep answering — through a link that is compatibility,
      // never the activation mechanism, which resolves through nothing.
      hold('0.1.0', {'mem': 'mem 0.1.0'});
      mountOldLayout(current: '0.1.0');

      expect(layoutOf().adopt(const [stream]).single.shimmed, ['mem']);

      final shim = p.join(legacyPrefix, 'mem');
      expect(FileSystemEntity.typeSync(shim, followLinks: false),
          FileSystemEntityType.link);
      expect(Link(shim).targetSync(), pathEntry('mem'));
      // Not merely a link: the name still runs, which is the whole claim.
      final ran = Process.runSync(shim, const []);
      expect(ran.stdout, contains('mem 0.1.0'));
    });

    test('what is not provably ours is not touched, even under our own names', () {
      // The foreign entries here carry names this release also ships, which is
      // the only fixture that tests ownership at all: where the names differ,
      // nothing gets re-aimed anyway — there is no binary of ours to aim it at,
      // and that miss would rescue an installer with no ownership check in it.
      hold('0.1.0', {
        'mem': 'mem 0.1.0',
        'place': 'place 0.1.0',
        'llm': 'llm 0.1.0',
      });
      mountOldLayout(current: '0.1.0');

      // Somebody else's `place`, reached by a link out of our home.
      final outsider = p.join(root.path, 'elsewhere');
      Directory(outsider).createSync();
      File(p.join(outsider, 'place')).writeAsStringSync(script('echo "theirs"'));
      Link(p.join(legacyPrefix, 'place')).deleteSync();
      Link(p.join(legacyPrefix, 'place')).createSync(p.join(outsider, 'place'));

      // And somebody else's `llm`, a real binary sitting on the PATH — what a
      // developer install leaves behind.
      Link(p.join(legacyPrefix, 'llm')).deleteSync();
      final foreign = File(p.join(legacyPrefix, 'llm'))
        ..writeAsStringSync(script('echo "not ours"'));

      expect(layoutOf().adopt(const [stream]).single.shimmed, ['mem'],
          reason: 'only the entry we can prove we created is re-aimed');

      expect(Link(p.join(legacyPrefix, 'place')).targetSync(),
          p.join(outsider, 'place'),
          reason: 'a link out of our home is not ours to re-aim');
      expect(FileSystemEntity.typeSync(foreign.path, followLinks: false),
          FileSystemEntityType.file);
      expect(foreign.readAsStringSync(), contains('not ours'),
          reason: 'a real file under our own name is still somebody else\'s');
    });

    test('adoption is idempotent — the second pass finds nothing to do', () {
      hold('0.1.0', {'mem': 'mem 0.1.0'});
      mountOldLayout(current: '0.1.0');

      expect(layoutOf().adopt(const [stream]), hasLength(1));
      expect(layoutOf().adopt(const [stream]), isEmpty,
          reason: 'the marker it detects is the pointer it removes');
      expect(VersionStore(home: home, prefix: prefix).currentVersion(stream), '0.1.0');
    });

    test('a machine with no old layout is left alone', () {
      // The disjoint half. A clean machine — and any machine already on this
      // store — must pass through adoption having written nothing at all.
      hold('0.2.0', {'mem': 'mem 0.2.0'});
      final store = VersionStore(home: home, prefix: prefix);
      store.activate(stream, '0.2.0');
      final before = File(p.join(home, 'state.json')).readAsStringSync();

      expect(layoutOf().adopt(const [stream]), isEmpty);

      expect(File(p.join(home, 'state.json')).readAsStringSync(), before);
      expect(store.currentVersion(stream), '0.2.0');
      expect(Directory(legacyPrefix).existsSync(), isFalse,
          reason: 'adoption must not create the directory it looks for');
    });

    test('nothing at all on the machine is not an error', () {
      expect(layoutOf().adopt(const [stream]), isEmpty);
      expect(Directory(home).existsSync(), isFalse);
    });

    test('under Windows semantics the shim is aimed at the .exe the store actually wrote', () {
      // The law lives in VersionStore.prefixName; the shim has to ask it
      // rather than build the bare name itself, or the link points at a file
      // substitute() never wrote.
      hold('0.1.0', {'mem': 'mem 0.1.0'});
      mountOldLayout(current: '0.1.0');

      final store = VersionStore(home: home, prefix: prefix, windowsSemantics: true);
      final layout = LegacyLayout(home: home, legacyPrefix: legacyPrefix, store: store);

      expect(layout.adopt(const [stream]).single.shimmed, ['mem']);

      expect(File(p.join(prefix, 'mem.exe')).existsSync(), isTrue,
          reason: 'substitute must have written the .exe name');
      final shim = p.join(legacyPrefix, 'mem');
      expect(Link(shim).targetSync(), p.join(prefix, 'mem.exe'),
          reason: 'the shim must forward to the name the store actually holds');
    });
  });

  group('through the command', () {
    /// The wiring, which is half the design: adoption that has to be typed is a
    /// hole with a name on it, so it rides the top of the ordinary verbs.
    BentosRunner runner(StringBuffer out, StringBuffer err, {String? path}) =>
        BentosRunner(
          out: out,
          err: err,
          host: const HostPlatform('linux', 'x64'),
          environment: {if (path != null) 'PATH': path},
          config: BentosConfig(
            home: home,
            prefix: prefix,
            legacyPrefix: legacyPrefix,
            streams: const {'bentos-userland': StreamConfig(name: 'bentos-userland')},
          ),
        );

    test('`list` adopts the machine before it reports on it', () async {
      hold('0.1.0', {'mem': 'mem 0.1.0'});
      mountOldLayout(current: '0.1.0');

      final out = StringBuffer();
      final err = StringBuffer();
      await runner(out, err, path: prefix).run(['list']);

      expect(out.toString(), contains('adopted bentos-userland 0.1.0'));
      expect(out.toString(), contains('bentos-userland  0.1.0'));
      expect(VersionStore(home: home, prefix: prefix).currentVersion(stream), '0.1.0');
    });

    test('`list` says out loud when something answers our name first', () async {
      hold('0.1.0', {'mem': 'mem 0.1.0'});
      mountOldLayout(current: '0.1.0');

      final ahead = p.join(root.path, 'ahead');
      Directory(ahead).createSync();
      File(p.join(ahead, exeName('mem'))).writeAsStringSync(script('echo "someone else"'));

      final out = StringBuffer();
      final err = StringBuffer();
      await runner(out, err, path: [ahead, prefix].join(pathSep)).run(['list']);

      // On stdout with the listing: it is a finding about the machine, and on
      // stderr it disappeared under `bentos list > file`.
      expect(out.toString(), contains('shadowed'));
      expect(out.toString(), contains(p.join(ahead, exeName('mem'))));
    });

    test('and stays quiet when nothing does', () async {
      hold('0.1.0', {'mem': 'mem 0.1.0'});
      mountOldLayout(current: '0.1.0');

      final out = StringBuffer();
      final err = StringBuffer();
      await runner(out, err, path: [prefix, '/usr/bin'].join(pathSep)).run(['list']);

      expect(out.toString(), isNot(contains('shadowed')));
      expect(out.toString(), isNot(contains('not on your PATH')));
    });

    test('a prefix nobody can reach is said plainly', () async {
      hold('0.1.0', {'mem': 'mem 0.1.0'});
      mountOldLayout(current: '0.1.0');

      final out = StringBuffer();
      final err = StringBuffer();
      await runner(out, err, path: ['/usr/bin', '/bin'].join(pathSep)).run(['list']);

      expect(out.toString(), contains('is not on your PATH'));
    });
  });

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

      // The same file, on the other side of our prefix: order is the whole
      // difference between a finding and a non-event.
      final shadows = PathShadows(prefix: prefix, pathDirs: [prefix, behind]);
      expect(
          shadows.ahead('mem',
              ourArtifact: store.artifactPath(stream, '0.2.0', 'mem')),
          isNull);
    });

    test('our own bytes ahead of us are ours, not a stranger', () {
      // What the shim itself looks like from here: the old prefix answers
      // first, and what it answers with is the binary we installed. Reporting
      // that as a stranger would cry wolf on every adopted machine.
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
      // Same law as VersionStore.prefixName, checked from the other side: a
      // bare "mem" ahead of us on the PATH is not what a Windows shell would
      // resolve to "mem" at all, so the finding has to look for "mem.exe".
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
}
