import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The seam guard, with teeth: the literal `.place` marker/layout string must
/// appear in exactly one source file — `residence.dart`. Any other component
/// that hard-codes `.place/…` has gone behind the residence seam, breaking the
/// swappability the API exists to protect.
void main() {
  test('the .place layout literal lives only in residence.dart', () {
    final srcDir = Directory(p.join(Directory.current.path, 'lib', 'src'));
    final offenders = <String>[];

    for (final entity in srcDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (p.basename(entity.path) == 'residence.dart') continue;
      // The tell is a hard-coded `.place` string literal in code — prose in
      // doc comments is not a seam breach.
      if (entity.readAsStringSync().contains("'.place'")) {
        offenders.add(p.relative(entity.path, from: Directory.current.path));
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'these files construct .place paths outside Residence: $offenders',
    );
  });
}
