import 'dart:io';

import 'package:bentos_userland/src/manifest/atom_editor.dart';
import 'package:bentos_userland/src/manifest/atom_serializer.dart';
import 'package:bentos_userland/src/manifest/edit_op.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

/// CONTRACT — the proof that matters: an edit produces a MINIMAL diff.
/// parse → apply one op → serialize must touch ONLY the changed element; every
/// other line is byte-identical. And the idempotency law is proven against a
/// REAL flat tree atom (anamnesis.xml), not just synthetic fixtures — units
/// over synthetic strings hide serialization drift the live genome would catch
/// (smoke-test-catches-what-fake-device-cannot).
void main() {
  const editor = AtomEditor();

  // The live tree sits beside this package in the workspace checkout.
  const realAtomPath = '../bentos-tree/faculty/anamnesis/anamnesis.xml';

  // A realistic flat multi-element atom, already in canonical form (so the only
  // diff a round-trip yields is the edit itself).
  String canonical() => serializeAtom(XmlDocument.parse(
        '<atom id="alfred.soul" v="3.0">'
        '<telos>a co-founder</telos>'
        '<capacity name="recollection">gather yourself</capacity>'
        '<capacity name="inscription">lay yourself down</capacity>'
        '<principle name="north-star">advance BentOS</principle>'
        '<antipattern name="voice-drift">vanilla</antipattern>'
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

  test('idempotency holds on the REAL flat tree atom (anamnesis.xml)', () {
    final file = File(realAtomPath);
    if (!file.existsSync()) {
      markTestSkipped('bentos-tree not checked out beside this package');
      return;
    }
    final raw = file.readAsStringSync();
    final once = serializeAtom(XmlDocument.parse(raw));
    final twice = serializeAtom(XmlDocument.parse(once));
    expect(twice, once, reason: 'fixed point must hold on the live genome');
    expect(once, contains('id="anamnesis.faculty"'),
        reason: 'canonical id attr must survive serialization');
  });

  test('the ticket acceptance: set @v on the real atom keeps id', () {
    final file = File(realAtomPath);
    if (!file.existsSync()) {
      markTestSkipped('bentos-tree not checked out beside this package');
      return;
    }
    final before = serializeAtom(XmlDocument.parse(file.readAsStringSync()));
    final after = editAndSerialize(before, const EditOp(
      verb: EditVerb.set, targetKind: TargetKind.attribute, target: 'v', value: '0.3',
    ));
    expect(after, contains('id="anamnesis.faculty"'));
    expect(after, contains('v="0.3"'));
    final delta = changedLines(before, after);
    expect(delta.every((l) => l.contains('<atom')), isTrue, reason: 'got: $delta');
  });

  test('the ticket acceptance: add principle works on a flat atom', () {
    final before = canonical();
    final after = editAndSerialize(before, const EditOp(
      verb: EditVerb.add, targetKind: TargetKind.element,
      target: 'principle', name: 'form', content: 'form matters',
    ));
    expect(after, contains('form matters'));
    // Pure addition: every line of `before` survives verbatim.
    for (final line in before.split('\n')) {
      expect(after.split('\n'), contains(line));
    }
  });

  test('setting one capacity body changes only that capacity\'s line(s)', () {
    final before = canonical();
    final after = editAndSerialize(before, const EditOp(
      verb: EditVerb.set, targetKind: TargetKind.element,
      target: 'capacity', name: 'recollection', content: 'gather whole',
    ));
    final delta = changedLines(before, after);
    expect(
        delta.every(
            (l) => l.contains('recollection') || l.contains('gather whole')),
        isTrue,
        reason: 'only the recollection capacity may move; got: $delta');
    // The untouched sibling survives verbatim.
    expect(after, contains('lay yourself down'));
  });

  test('removing one antipattern leaves every other element byte-identical', () {
    final before = canonical();
    final after = editAndSerialize(before, const EditOp(
      verb: EditVerb.remove, targetKind: TargetKind.element,
      target: 'antipattern', name: 'voice-drift',
    ));
    // Every surviving line of `after` existed verbatim in `before` (pure deletion).
    for (final line in after.split('\n')) {
      expect(before.split('\n'), contains(line), reason: 'new/altered line leaked: $line');
    }
    expect(after, isNot(contains('voice-drift')));
  });

  test('re-serialization is identity on canonical output', () {
    final once = canonical();
    expect(serializeAtom(XmlDocument.parse(once)), once);
  });
}
