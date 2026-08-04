import 'dart:convert';
import 'dart:io';

import 'package:bentos_userland/installer.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fixture_binary.dart';

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

  /// One fixture release: each executable is a real compiled binary that
  /// prints its own name and version, so "installed" can be proven by running
  /// the thing — on every platform the suite runs on, not just the ones whose
  /// shell reads a shebang.
  String publish(String version, List<String> names, {Map<String, String>? corruptHash}) {
    final artifacts = <Map<String, Object?>>[];
    for (final name in names) {
      final body = FixtureBinaries.bytesFor('$name $version');
      final asset = '$name-$host';
      File(p.join(streamDir, asset)).writeAsBytesSync(body);
      artifacts.add({
        'name': name,
        'platform': '$host',
        'asset': asset,
        'sha256': corruptHash?[name] ?? sha256.convert(body).toString(),
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

  /// The PATH the runner sees. Injected rather than inherited: the shadow
  /// reading is about the caller's PATH, and a gate that let the operator's own
  /// through would be asserting against whatever is installed on the machine
  /// running the suite.
  BentosRunner runnerWith(StringBuffer out, StringBuffer err, {List<String>? path}) => BentosRunner(
        out: out,
        err: err,
        host: host,
        environment: {'PATH': (path ?? [prefix]).join(Platform.isWindows ? ';' : ':')},
        config: BentosConfig(
          home: home,
          prefix: prefix,
          // Under this test's own root: the runner now looks at the old prefix
          // on every verb, and no gate may look at the operator's `~/.local/bin`.
          legacyPrefix: p.join(root.path, 'legacy-bin'),
          streams: {'bentos-userland': StreamConfig(name: 'bentos-userland', dir: streamDir)},
        ),
      );

  Future<(int, String, String)> run(List<String> args, {List<String>? path}) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final runner = runnerWith(out, err, path: path);
    await runner.run(args);
    return (runner.exitCode, out.toString(), err.toString());
  }

  String pathEntry(String name) =>
      p.join(prefix, Platform.isWindows ? '$name.exe' : name);

  /// The bytes at a name in the prefix, as a hash — the witness every report
  /// gate below is judged against, taken before and after the command.
  String bytesAt(String name) =>
      sha256.convert(File(pathEntry(name)).readAsBytesSync()).toString();

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

  /// The report is about the prefix, and these gates witness the prefix.
  ///
  /// Asserting against what the version store holds is exactly the reading that
  /// was wrong: the store held every artifact in both the cured and the
  /// untouched case, so a gate built on it agrees with the defect. What each
  /// test pins is the printed word against what happened to the *bytes at the
  /// name*, read before and after the command.
  group('install reports what happened to the prefix', () {
    setUp(() async {
      publish('0.2.0', ['mem', 'place']);
      await run(['install']);
    });

    test('a cured name is restored, and the bytes say so', () async {
      final intact = File(pathEntry('mem')).readAsBytesSync();
      File(pathEntry('mem')).writeAsStringSync('#!/bin/sh\necho foreign\n');
      final drifted = File(pathEntry('mem')).readAsBytesSync();
      expect(drifted, isNot(intact));

      final (code, out, _) = await run(['install']);

      expect(code, 0);
      expect(File(pathEntry('mem')).readAsBytesSync(), intact,
          reason: 'the bytes were put back');
      expect(out, contains('restored'));
      expect(RegExp(r'restored\s+:.*\bmem\b').hasMatch(out), isTrue,
          reason: 'the name whose bytes changed is the one reported restored');
      expect(RegExp(r'unchanged\s+:.*\bmem\b').hasMatch(out), isFalse,
          reason: 'a machine that was just repaired is never called unchanged');
      // Disjoint in the same reading: the name nobody touched keeps its word.
      expect(RegExp(r'unchanged\s+:.*\bplace\b').hasMatch(out), isTrue);
    });

    test('an untouched name is unchanged, and its bytes never move', () async {
      final before = {
        for (final name in ['mem', 'place'])
          name: File(pathEntry(name)).statSync().modified,
      };

      final (code, out, _) = await run(['install']);

      expect(code, 0);
      expect(out, contains('unchanged'));
      expect(out, isNot(contains('restored')),
          reason: 'nothing was cured, so nothing may claim to have been');
      for (final name in ['mem', 'place']) {
        expect(File(pathEntry(name)).statSync().modified, before[name],
            reason: '$name was not rewritten');
      }
    });

    test('a first install is installed and never unchanged', () async {
      publish('0.3.0', ['mem', 'place']);
      final (code, out, _) = await run(['install']);

      expect(code, 0);
      expect(RegExp(r'installed\s+:.*\bmem\b').hasMatch(out), isTrue);
      expect(out, isNot(contains('unchanged')));
    });
  });

  /// Updating onto a version whose artifacts are already materialized — the
  /// machine of someone who went up, did not like it, rolled back, and is going
  /// up again. Nothing is fetched there, so every word in the report comes from
  /// what activation did to the prefix and from nothing else.
  ///
  /// The pair is disjoint on the axis that produced the defect: artifacts held
  /// against a machine that has to download them. Both are driven through the
  /// same verb and witnessed by hashing the bytes at the name before and after.
  group('update over a version already held', () {
    /// The bytes at each name, which is the only witness allowed here: the
    /// version store holds every artifact in both cases of the pair, so a gate
    /// reading the store agrees with a report that is lying.
    Map<String, String> bytesInPrefix(List<String> names) =>
        {for (final name in names) name: bytesAt(name)};

    List<String> movedBetween(Map<String, String> before, Map<String, String> after) =>
        [for (final name in before.keys) if (before[name] != after[name]) name];

    const names = ['bentos', 'mem', 'place'];

    test('every name whose bytes moved is named, and the cause is the move', () async {
      publish('0.2.0', names);
      await run(['install']);
      publish('0.3.0', names);
      await run(['install']);
      await run(['rollback']);

      final before = bytesInPrefix(names);
      final (code, out, _) = await run(['update']);
      final after = bytesInPrefix(names);

      expect(code, 0);
      expect(movedBetween(before, after), unorderedEquals(names),
          reason: 'the premise of this gate: all three binaries were rewritten');

      // The defect this pins: a command that rewrote every binary on the PATH
      // and printed `unchanged` over it. Each name that moved is named, and no
      // name that moved is called untouched.
      for (final name in names) {
        expect(RegExp('restored\\s+:.*\\b$name\\b').hasMatch(out), isTrue,
            reason: '$name was rewritten and the report has to say so');
        expect(RegExp('unchanged\\s+:.*\\b$name\\b').hasMatch(out), isFalse);
      }

      // And the cause is true: nothing had drifted — the machine moved from a
      // version it was legitimately on.
      expect(out, contains('(replacing 0.2.0)'));
      expect(out, isNot(contains('had drifted')));
    });

    test('a virgin machine downloads, and says installed — the same verb', () async {
      // The other half of the pair, disjoint by construction: nothing is
      // materialized, so the same command reaches the network and every word
      // comes from a fetch. Both halves have to be green for either to mean
      // anything.
      publish('0.3.0', names);

      final (code, out, _) = await run(['update']);

      expect(code, 0);
      for (final name in names) {
        expect(File(pathEntry(name)).existsSync(), isTrue);
        expect(RegExp('installed\\s+:.*\\b$name\\b').hasMatch(out), isTrue);
      }
      expect(out, isNot(contains('unchanged')));
      expect(out, isNot(contains('restored')));
    });

    test('one command, one report — never two boxes contradicting each other', () async {
      // `update` installs itself and then the set. Two reports meant the same
      // name read `restored` in the first box and `unchanged` in the second,
      // and a caller cannot be told both about one command.
      publish('0.2.0', names);
      await run(['install']);
      publish('0.3.0', names);

      final (code, out, _) = await run(['update']);

      expect(code, 0);
      expect('unchanged'.allMatches(out).length, lessThanOrEqualTo(1));
      expect(RegExp(r'→').allMatches(out).length, 1,
          reason: 'one act, one headline');
    });

    test('the caller is told their own bentos was replaced', () async {
      // The most delicate thing this program does, and it used to happen in
      // silence: the next `bentos` the person types is a different binary.
      publish('0.2.0', names);
      await run(['install']);
      publish('0.3.0', names);

      final before = bytesInPrefix(names);
      final (_, out, _) = await run(['update']);
      final after = bytesInPrefix(names);

      expect(movedBetween(before, after), contains('bentos'));
      expect(out, contains('bentos replaced itself'));
      expect(out, contains('0.3.0'));
    });

    test('a first install replaced nothing, and does not claim to', () async {
      // Found by running the real binary on a machine with nothing: every name
      // is written, so the notice fired over a `bentos` that had never existed.
      // The claim is about displacing something the caller may be running, and
      // on a virgin machine there is nothing to displace.
      publish('0.2.0', names);

      final (_, out, _) = await run(['update']);

      expect(RegExp(r'installed\s+:.*\bbentos\b').hasMatch(out), isTrue);
      expect(out, isNot(contains('replaced itself')));
    });

    test('a command that leaves bentos alone says nothing about it', () async {
      // Disjoint: same machine, the notice's condition absent. Re-running an
      // update that has nothing to do rewrites no binary, and the line that
      // announces a replacement must not appear over one that never happened.
      publish('0.2.0', names);
      await run(['install']);

      final before = bytesInPrefix(names);
      final (_, out, _) = await run(['update']);
      final after = bytesInPrefix(names);

      expect(movedBetween(before, after), isEmpty);
      expect(out, isNot(contains('replaced itself')));
    });

    // `self-update` names must be an upper bound and not a suggestion:
    // `openVersion` carries every name forward into the new version's
    // directory regardless of what was asked for, so `activate` iterating that
    // whole directory instead of the request is how a one-name ask moved the
    // other nine. The witness is the same as the pair above: bytes at each
    // name, before and after, never the version store's own bookkeeping.
    test('self-update moves bentos and leaves every other name untouched', () async {
      publish('0.2.0', names);
      await run(['install']);
      publish('0.3.0', names);

      final before = bytesInPrefix(names);
      final (code, out, _) = await run(['self-update']);
      final after = bytesInPrefix(names);

      expect(code, 0);
      expect(movedBetween(before, after), ['bentos'],
          reason: 'self-update asked for one name; only that name may move');
      expect(RegExp(r'installed\s+:.*\bbentos\b').hasMatch(out), isTrue);
      expect(RegExp(r'unchanged\s+:.*\bmem\b').hasMatch(out), isTrue);
      expect(RegExp(r'unchanged\s+:.*\bplace\b').hasMatch(out), isTrue);
    });
  });

  /// Rollback moves as many binaries as an update does, including the caller's
  /// own, and reported it in one line naming no name.
  group('rollback reports what it did, in the words an install uses', () {
    const names = ['bentos', 'mem', 'place'];

    test('the names that went back are named, and so is the swap of bentos', () async {
      publish('0.2.0', names);
      await run(['install']);
      publish('0.3.0', names);
      await run(['install']);

      final before = {for (final n in names) n: bytesAt(n)};
      final (code, out, _) = await run(['rollback']);
      final moved = [for (final n in names) if (before[n] != bytesAt(n)) n];

      expect(code, 0);
      expect(moved, unorderedEquals(names));
      for (final name in names) {
        expect(RegExp('restored\\s+:.*\\b$name\\b').hasMatch(out), isTrue);
      }
      expect(out, contains('rolled back from 0.3.0'));
      expect(out, contains('bentos replaced itself'));
      expect(out, contains('the next `bentos` you run is 0.2.0'));
      // Nothing was fetched to do it, and nothing may claim otherwise.
      expect(out, isNot(contains('installed')));
    });

    test('a rollback with nowhere to go moves nothing and announces nothing', () async {
      // Disjoint: the same verb on a machine with one version. Nothing is
      // written, so no name may be named and the replacement notice — which is
      // the line a caller will act on — must not be printed over a swap that
      // never happened.
      publish('0.2.0', names);
      await run(['install']);

      final before = {for (final n in names) n: bytesAt(n)};
      final (code, out, err) = await run(['rollback']);

      expect(code, 1);
      expect(err, contains('no previous version'));
      expect(out, isEmpty);
      for (final n in names) {
        expect(bytesAt(n), before[n]);
      }
    });
  });

  /// A finding is a finding, whichever of the three it is — and it is content
  /// of the report, not diagnostics of the run. The pairs are disjoint: the same
  /// machine, one condition present and then absent.
  group('every finding raises the code and lands on stdout', () {
    late String ahead;

    setUp(() async {
      publish('0.2.0', ['mem', 'place']);
      await run(['install']);
      ahead = p.join(root.path, 'ahead');
      Directory(ahead).createSync(recursive: true);
    });

    test('a shadowed name is a finding, in stdout, exit 2', () async {
      File(p.join(ahead, 'mem')).writeAsStringSync('#!/bin/sh\necho someone else\n');

      final (code, out, _) = await run(['list'], path: [ahead, prefix]);

      expect(code, 2, reason: 'you run none of what was installed at that name');
      expect(out, contains('shadowed'),
          reason: 'stdout, so `bentos list > file` cannot fabricate health');
      expect(out, contains(p.join(ahead, 'mem')));
    });

    test('no shadow, no finding — same machine, exit 0', () async {
      final (code, out, _) = await run(['list'], path: [ahead, prefix]);

      expect(code, 0);
      expect(out, isNot(contains('shadowed')));
    });

    test('a prefix off the PATH is a finding, in stdout, exit 2', () async {
      final (code, out, _) = await run(['list'], path: [ahead]);

      expect(code, 2, reason: 'nothing installed here is what anyone runs');
      expect(out, contains('is not on your PATH'));
    });

    test('the same name ahead of us, but ours, is no finding', () async {
      // A shim: the bytes ahead are the artifact we installed, so the person
      // does run what we put there and there is nothing to say.
      File(p.join(ahead, 'mem'))
          .writeAsBytesSync(File(pathEntry('mem')).readAsBytesSync());

      final (code, out, _) = await run(['list'], path: [ahead, prefix]);

      expect(code, 0);
      expect(out, isNot(contains('shadowed')));
    });
  });
}
