// The laws that cross every component (design §laws), checked by import.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final placeSrc = Directory(p.join(Directory.current.path, 'lib', 'src', 'place'));

  Iterable<File> dartFiles(Directory d) => d.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  test('nothing under place/ imports the Git package or names a Git object', () {
    final offenders = <String>[];
    for (final f in dartFiles(placeSrc)) {
      final s = f.readAsStringSync();
      if (RegExp(r"import\s+'(package:bentos_userland/)?(src/|\.\./)*git/").hasMatch(s) || RegExp(r"import\s+'package:bentos_userland/git\.dart'").hasMatch(s)) {
        offenders.add(p.relative(f.path, from: placeSrc.path));
      }
    }
    // Red today: lib/src/place/ still holds the built primitive's superrepo
    // half, which this design retires. Green is the retirement landing.
    expect(offenders, isEmpty, reason: 'the place never speaks Git; everything it does to its own record it does through the entity');
  });

  test('only arrangement, presence and constellation import the entity', () {
    final contract = Directory(p.join(placeSrc.path, 'contract'));
    final allowed = {'arrangement.dart', 'presence.dart', 'constellation.dart', 'copy_gate.dart', 'contract.dart', 'record.dart', 'survey.dart', 'resolver.dart', 'face.dart', 'place.dart'};
    // At contract altitude every page names the entity's *types*; the law binds
    // holders of a `Copy`, which the build enforces. Here: no file outside the
    // contract dir may reach the entity, and no contract file may reach Git.
    for (final f in dartFiles(contract)) {
      expect(allowed, contains(p.basename(f.path)));
      expect(f.readAsStringSync(), isNot(contains("git")), reason: '${p.basename(f.path)} names Git');
    }
  });
}
