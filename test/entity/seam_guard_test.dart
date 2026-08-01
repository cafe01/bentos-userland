import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The seam guard, with teeth — the entity's own, in the idiom `place` set.
///
/// The port exists because `IOOverrides` does not reach subprocesses: every
/// test above it is hermetic **only** while the process name lives behind the
/// seam. A file that spawns Git directly has voided that, and the green it
/// reports is worthless.
///
/// The tell is the Dart string literal `'git'`. The shim is deliberately not
/// caught by it: that file is shell, Dart never runs in the hook path, and its
/// text carries no Dart literal — the exception is a fact about the tell, not a
/// hole punched in the law.
void main() {
  test('the git process literal lives only under src/entity/git/', () {
    final entityDir = Directory(p.join(Directory.current.path, 'lib', 'src', 'entity'));
    final offenders = <String>[];

    for (final file in entityDir.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      if (p.split(p.relative(file.path, from: entityDir.path)).first == 'git') continue;
      if (file.readAsStringSync().contains("'git'")) {
        offenders.add(p.relative(file.path, from: Directory.current.path));
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'these files spawn git outside the port: $offenders',
    );
  });

  test('the entity never reaches into another primitive\'s control plane', () {
    final entityDir = Directory(p.join(Directory.current.path, 'lib', 'src', 'entity'));
    final offenders = <String>[];

    for (final file in entityDir.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      if (file.readAsStringSync().contains("'.place'")) {
        offenders.add(p.relative(file.path, from: Directory.current.path));
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'the entity is a tenant: it asks for a plot, it never builds the '
          'path to one — $offenders',
    );
  });
}
