import 'dart:io';

import 'package:bentos_userland/installer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The store's own mechanism, under the three pressures that would let
/// substitution look like it works while not working: a rename that cannot be
/// done, a binary that is executing while it is replaced, and a host that
/// refuses to rename over a running file.
void main() {
  late Directory root;
  late String home;
  late String prefix;

  const stream = 'bentos-userland';

  setUp(() {
    root = Directory.systemTemp.createTempSync('bentos-substitution-');
    home = p.join(root.path, 'bentos-home');
    prefix = p.join(home, 'bin');
  });

  tearDown(() => root.deleteSync(recursive: true));

  /// Materialize a version by hand — this suite is about placement, so it never
  /// goes through a manifest.
  void hold(String version, Map<String, String> bodies) {
    final dir = Directory(p.join(home, 'versions', stream, version, 'bin'))
      ..createSync(recursive: true);
    for (final entry in bodies.entries) {
      final file = File(p.join(dir.path, entry.key))..writeAsStringSync(entry.value);
      Process.runSync('chmod', ['+x', file.path]);
    }
  }

  String script(String text) => '#!/bin/sh\n$text\n';

  test('the staging area is inside home, so a rename never crosses a filesystem', () {
    final store = VersionStore(home: home, prefix: prefix);
    // The structural half of the EXDEV guarantee: both ends of every rename are
    // under one root, so no deployment can put them on separate volumes without
    // moving the whole of `~/.bentos`.
    expect(p.isWithin(home, store.stagingDir), isTrue);
    expect(p.isWithin(home, prefix), isTrue);
  });

  test('a rename that cannot be done comes out — nothing falls back to copying', () {
    hold('0.2.0', {'mem': script('echo "mem 0.2.0"')});

    // EXDEV as the kernel reports it: `rename(2)` across filesystems does not
    // degrade to a copy, it fails. A store that caught this and copied instead
    // would pass every other gate in this file while silently giving up the one
    // guarantee substitution rests on — that the file at the destination is
    // never a half-written binary.
    final store = VersionStore(
      home: home,
      prefix: prefix,
      rename: (from, to) => throw FileSystemException(
        'Cannot rename file to \'$to\'',
        from,
        const OSError('Invalid cross-device link', 18),
      ),
    );

    expect(
      () => store.activate(stream, '0.2.0'),
      throwsA(isA<FileSystemException>()
          .having((e) => e.osError?.errorCode, 'errno', 18)),
    );
    // And the failure is not half-done: nothing was left on the PATH and the
    // pointer, which is written last, never moved.
    expect(File(p.join(prefix, 'mem')).existsSync(), isFalse);
    expect(store.currentVersion(stream), isNull);
  });

  test('the old file is displaced, never rewritten — the inode survives whole', () {
    // Why a running `bentos` can replace itself: substitution unlinks the old
    // inode and puts a new one at the name, so whoever still holds the old one
    // — a process executing it, above all — keeps a whole, unchanged file.
    //
    // A hard link taken before the swap is that holder, made observable. A
    // fallback that copied bytes over the destination instead of renaming would
    // write *through* this link and it would read the new version: this is the
    // filesystem-level falsification of the copy, and it needs no second volume.
    hold('0.2.0', {'mem': script('echo "mem 0.2.0"')});
    hold('0.3.0', {'mem': script('echo "mem 0.3.0"')});

    final store = VersionStore(home: home, prefix: prefix);
    store.activate(stream, '0.2.0');

    final onPath = p.join(prefix, 'mem');
    // A hard link and not a symlink: the witness has to be the inode itself,
    // where a symlink would just resolve the path again and read whatever is
    // there now. Dart has no hard-link call, so this is `ln`.
    final witness = p.join(root.path, 'witness');
    expect(Process.runSync('ln', [onPath, witness]).exitCode, 0);

    store.activate(stream, '0.3.0');

    expect(File(witness).readAsStringSync(), contains('mem 0.2.0'),
        reason: 'the old inode was written through — this is a copy, not a rename');
    expect(File(onPath).readAsStringSync(), contains('mem 0.3.0'));
  }, testOn: '!windows');

  test('where a running file cannot be renamed over, it is displaced first', () {
    // Windows semantics, driven on this host: the old binary goes to `.old`
    // before the new one takes the name. Injected rather than detected, so the
    // path that exists for Windows is exercised everywhere instead of only
    // where no gate has ever run.
    hold('0.2.0', {'bentos': script('echo "bentos 0.2.0"')});
    hold('0.3.0', {'bentos': script('echo "bentos 0.3.0"')});

    final store = VersionStore(home: home, prefix: prefix, windowsSemantics: true);
    store.activate(stream, '0.2.0');
    store.activate(stream, '0.3.0');

    final displaced = File(p.join(prefix, 'bentos.exe.old'));
    expect(displaced.existsSync(), isTrue);
    expect(displaced.readAsStringSync(), contains('bentos 0.2.0'));
    expect(File(p.join(prefix, 'bentos.exe')).readAsStringSync(), contains('bentos 0.3.0'));

    // A third replacement clears the previous leftover rather than accreting.
    hold('0.4.0', {'bentos': script('echo "bentos 0.4.0"')});
    store.activate(stream, '0.4.0');
    expect(displaced.readAsStringSync(), contains('bentos 0.3.0'));
    expect(File(p.join(prefix, 'bentos.exe')).readAsStringSync(), contains('bentos 0.4.0'));
  });

  test('POSIX displaces nothing — there is no .old on a host that does not need one', () {
    hold('0.2.0', {'bentos': script('echo "bentos 0.2.0"')});
    hold('0.3.0', {'bentos': script('echo "bentos 0.3.0"')});

    final store = VersionStore(home: home, prefix: prefix, windowsSemantics: false);
    store.activate(stream, '0.2.0');
    store.activate(stream, '0.3.0');

    expect(File(p.join(prefix, 'bentos.old')).existsSync(), isFalse);
  });

  test('under Windows semantics the prefix name carries .exe, and every reader agrees', () {
    // The seam this test exists to prove: namesInPrefix, drift and substitute
    // all resolve the same on-disk name. Broken on purpose once (dropping
    // _prefixName from namesInPrefix alone) to see this fail before trusting
    // it — with the fix in place, a name materialized as "bentos" lands on the
    // PATH as "bentos.exe" and every one of the three agrees it is there.
    hold('0.2.0', {'bentos': script('echo "bentos 0.2.0"')});

    final store = VersionStore(home: home, prefix: prefix, windowsSemantics: true);
    store.activate(stream, '0.2.0');

    expect(File(p.join(prefix, 'bentos.exe')).existsSync(), isTrue,
        reason: 'substitute must write the .exe name on Windows');
    expect(File(p.join(prefix, 'bentos')).existsSync(), isFalse,
        reason: 'nothing should be written under the bare name on Windows');
    expect(store.namesInPrefix(['bentos']), {'bentos'},
        reason: 'namesInPrefix must find the .exe file it just wrote');
    expect(store.drift(stream).single.state, DriftState.installed,
        reason: 'drift must compare against the same .exe name substitute wrote, '
            'never report a fresh install as drifted');
  });
}
