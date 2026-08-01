import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The seam guards, with teeth — one file, because there is one law and two
/// sisters under it.
///
/// The Git port exists because `IOOverrides` does not reach subprocesses: every
/// test above it is hermetic **only** while the process name lives behind the
/// seam. A file that spawns Git directly has voided that, and the green it
/// reports is worthless. The port is no longer the entity's: `Place` speaks Git
/// too, so the guard covers both primitives, and the port itself answers to
/// neither.
///
/// The tell is the Dart string literal `'git'`. The shim is deliberately not
/// caught by it: that file is shell, Dart never runs in the hook path, and its
/// text carries no Dart literal — the exception is a fact about the tell, not a
/// hole punched in the law.
void main() {
  final srcDir = Directory(p.join(Directory.current.path, 'lib', 'src'));

  List<File> filesUnder(List<String> subdirectories) => [
        for (final name in subdirectories)
          ...Directory(p.join(srcDir.path, name))
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')),
      ];

  String rel(File f) => p.relative(f.path, from: Directory.current.path);

  test('the git process literal lives only under src/git/', () {
    final offenders = [
      for (final file in filesUnder(['entity', 'place']))
        if (file.readAsStringSync().contains("'git'")) rel(file),
    ];

    expect(
      offenders,
      isEmpty,
      reason: 'these files spawn git outside the port: $offenders',
    );
  });

  test('the .place layout literal lives only in place.dart', () {
    final offenders = [
      for (final file in filesUnder(['entity', 'place', 'git']))
        if (p.basename(file.path) != 'place.dart' &&
            file.readAsStringSync().contains("'.place'"))
          rel(file),
    ];

    expect(
      offenders,
      isEmpty,
      reason: 'these files construct .place paths outside place.dart — a tenant '
          'asks for a plot, it never builds the path to one: $offenders',
    );
  });

  test('the substrate answers to neither sister', () {
    final offenders = [
      for (final file in filesUnder(['git']))
        if (file.readAsStringSync().contains(RegExp(r"import '.*(entity|place)/")))
          rel(file),
    ];

    expect(
      offenders,
      isEmpty,
      reason: 'src/git must not depend on what stands on it: $offenders',
    );
  });
}
