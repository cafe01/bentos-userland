import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The seam guard, with teeth: the literal `.place` marker/layout string must
/// appear in exactly the files that own it — `residence.dart` (the old
/// model, still consumed by mem2), `place.dart` (the new primitive), and
/// `model/place_meta.dart` (the metadata loader shared by both, dual-mode
/// over `fs`). Transitional: collapses to `place.dart` alone once #11 retires
/// the old model. Any other component that hard-codes `.place/…` has gone
/// behind the seam, breaking the swappability the API exists to protect.
void main() {
  test('the .place layout literal lives only in its owning files', () {
    final srcDir = Directory(p.join(Directory.current.path, 'lib', 'src'));
    final offenders = <String>[];
    const owners = {'residence.dart', 'place.dart', 'place_meta.dart'};

    for (final entity in srcDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (owners.contains(p.basename(entity.path))) continue;
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
