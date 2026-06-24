import 'package:bentos_userland/src/manifest/atom_editor.dart';
import 'package:bentos_userland/src/manifest/atom_serializer.dart';
import 'package:bentos_userland/src/manifest/edit_op.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

/// CONTRACT — the proof that matters (ticket #45 "Delegation"): an edit produces a
/// MINIMAL diff. parse → apply one op → serialize must touch ONLY the changed
/// particle; every other line is byte-identical. This is what makes `edit` safe
/// for a bulk faculty pass — and the property unit-level assertions over a fake
/// filesystem cannot prove (smoke-test-catches-what-fake-device-cannot): it lives
/// in the serializer's real output, so it is asserted on real serialized text.
void main() {
  const editor = AtomEditor();

  // A realistic multi-particle atom, already in canonical form (so the only diff a
  // round-trip yields is the edit itself, never a canonicalization artifact).
  String canonical() => serializeAtom(XmlDocument.parse(
        '<atom v="3.0">'
        '<living-abstract>'
        '<essence>a co-founder</essence>'
        '<trait name="refined">form matters</trait>'
        '<trait name="loving">the engine</trait>'
        '<principle name="north-star">advance BentOS</principle>'
        '</living-abstract>'
        '<living-concrete>'
        '<knowledge name="origin">born before BentOS</knowledge>'
        '<antipattern name="voice-drift">vanilla</antipattern>'
        '</living-concrete>'
        '</atom>',
      ));

  String editAndSerialize(String source, EditOp op) {
    final doc = XmlDocument.parse(source);
    editor.apply(doc, op);
    return serializeAtom(doc);
  }

  Set<String> changedLines(String before, String after) {
    final b = before.split('\n').toSet();
    final a = after.split('\n').toSet();
    return a.difference(b)..addAll(b.difference(a));
  }

  test('setting one trait body changes only that trait\'s line(s)', () {
    final before = canonical();
    final after = editAndSerialize(before, const EditOp(
      verb: EditVerb.set, targetKind: TargetKind.particle,
      target: 'trait', name: 'refined', content: 'structure is everything',
    ));
    final delta = changedLines(before, after);
    expect(delta.every((l) => l.contains('refined') || l.contains('structure is everything')),
        isTrue,
        reason: 'only the refined trait may move; got: $delta');
    // The untouched loving trait survives verbatim.
    expect(after, contains('the engine'));
  });

  test('bumping v changes only the atom open tag', () {
    final before = canonical();
    final after = editAndSerialize(before, const EditOp(
      verb: EditVerb.set, targetKind: TargetKind.attribute, target: 'v', value: '4.0',
    ));
    final delta = changedLines(before, after);
    expect(delta.every((l) => l.contains('<atom')), isTrue, reason: 'got: $delta');
    expect(after, contains('v="4.0"'));
  });

  test('removing one antipattern leaves every other particle byte-identical', () {
    final before = canonical();
    final after = editAndSerialize(before, const EditOp(
      verb: EditVerb.remove, targetKind: TargetKind.particle,
      target: 'antipattern', name: 'voice-drift',
    ));
    // Every surviving line of `after` existed verbatim in `before` (pure deletion).
    for (final line in after.split('\n')) {
      expect(before.split('\n'), contains(line), reason: 'new/altered line leaked: $line');
    }
    expect(after, isNot(contains('voice-drift')));
  });

  test('a no-op edit is impossible to express, but re-serialization is identity', () {
    final once = canonical();
    expect(serializeAtom(XmlDocument.parse(once)), once);
  });
}
