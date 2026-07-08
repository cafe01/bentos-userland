import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The seam guard, with teeth: the literal `.place` marker/layout string must
/// appear only in `place.dart` — the primitive that owns the marker and the
/// layout beneath it. Any other component that hard-codes `.place/…` has gone
/// behind the seam, breaking the swappability the API exists to protect.
void main() {
  test('the .place layout literal lives only in place.dart', () {
    final srcDir = Directory(p.join(Directory.current.path, 'lib', 'src'));
    final offenders = <String>[];

    for (final entity in srcDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (p.basename(entity.path) == 'place.dart') continue;
      // The tell is a hard-coded `.place` string literal in code — prose in
      // doc comments is not a seam breach.
      if (entity.readAsStringSync().contains("'.place'")) {
        offenders.add(p.relative(entity.path, from: Directory.current.path));
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'these files construct .place paths outside place.dart: $offenders',
    );
  });
}
