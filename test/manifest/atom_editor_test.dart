import 'package:bentos_userland/src/manifest/atom_editor.dart';
import 'package:bentos_userland/src/manifest/edit_op.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

/// CONTRACT — [AtomEditor] applies a validated op to a DOM, honouring the realm
/// law and the member-split guard, raising [EditConflictException] when a legal op
/// meets an incompatible document. Pure DOM, zero IO.
void main() {
  const editor = AtomEditor();

  // A minimal single-file atom with both realms present.
  XmlDocument fixture() => XmlDocument.parse(
        '<atom v="1.0">'
        '<living-abstract>'
        '<essence>old essence</essence>'
        '<trait name="refined">form matters</trait>'
        '<principle name="north-star">advance BentOS</principle>'
        '</living-abstract>'
        '<living-concrete>'
        '<antipattern name="voice-drift">vanilla</antipattern>'
        '</living-concrete>'
        '</atom>',
      );

  XmlElement abstractOf(XmlDocument d) =>
      d.rootElement.getElement('living-abstract')!;
  XmlElement concreteOf(XmlDocument d) =>
      d.rootElement.getElement('living-concrete')!;

  group('add — appends to the particle\'s realm container', () {
    test('a new abstract trait lands in living-abstract', () {
      final d = fixture();
      editor.apply(d, const EditOp(
        verb: EditVerb.add, targetKind: TargetKind.particle,
        target: 'trait', name: 'loving', content: 'the engine',
      ));
      final added = abstractOf(d).childElements
          .where((e) => e.name.local == 'trait' && e.getAttribute('name') == 'loving');
      expect(added, hasLength(1));
      expect(added.single.innerText, 'the engine');
    });

    test('a new concrete pattern lands in living-concrete (realm derived, not asked)', () {
      final d = fixture();
      editor.apply(d, const EditOp(
        verb: EditVerb.add, targetKind: TargetKind.particle,
        target: 'pattern', name: 'organic-rewrite', content: 'rewrite whole',
      ));
      expect(concreteOf(d).childElements.any((e) => e.name.local == 'pattern'), isTrue);
      expect(abstractOf(d).childElements.any((e) => e.name.local == 'pattern'), isFalse);
    });

    test('adding a duplicate named particle is a conflict', () {
      final d = fixture();
      expect(
        () => editor.apply(d, const EditOp(
          verb: EditVerb.add, targetKind: TargetKind.particle,
          target: 'trait', name: 'refined', content: 'dup',
        )),
        throwsA(isA<EditConflictException>()),
      );
    });

    test('add creates an absent realm container (concrete may not exist yet)', () {
      final d = XmlDocument.parse(
        '<atom v="1.0"><living-abstract><essence>e</essence></living-abstract></atom>',
      );
      editor.apply(d, const EditOp(
        verb: EditVerb.add, targetKind: TargetKind.particle,
        target: 'knowledge', name: 'k', content: 'understood',
      ));
      expect(d.rootElement.getElement('living-concrete'), isNotNull);
    });
  });

  group('set — replaces body, preserves handle', () {
    test('set an existing trait\'s body', () {
      final d = fixture();
      editor.apply(d, const EditOp(
        verb: EditVerb.set, targetKind: TargetKind.particle,
        target: 'trait', name: 'refined', content: 'new body',
      ));
      final t = abstractOf(d).childElements.firstWhere((e) => e.getAttribute('name') == 'refined');
      expect(t.innerText, 'new body');
    });

    test('set a singleton creates-or-replaces (add≡set)', () {
      final d = fixture();
      editor.apply(d, const EditOp(
        verb: EditVerb.set, targetKind: TargetKind.particle,
        target: 'essence', content: 'new essence',
      ));
      expect(abstractOf(d).getElement('essence')!.innerText, 'new essence');
    });

    test('set an atom attribute writes the root scalar', () {
      final d = fixture();
      editor.apply(d, const EditOp(
        verb: EditVerb.set, targetKind: TargetKind.attribute,
        target: 'v', value: '2.0',
      ));
      expect(d.rootElement.getAttribute('v'), '2.0');
    });

    test('set an absent named particle is a conflict', () {
      final d = fixture();
      expect(
        () => editor.apply(d, const EditOp(
          verb: EditVerb.set, targetKind: TargetKind.particle,
          target: 'trait', name: 'ghost', content: 'x',
        )),
        throwsA(isA<EditConflictException>()),
      );
    });
  });

  group('remove / rename', () {
    test('remove detaches the element', () {
      final d = fixture();
      editor.apply(d, const EditOp(
        verb: EditVerb.remove, targetKind: TargetKind.particle,
        target: 'antipattern', name: 'voice-drift',
      ));
      expect(concreteOf(d).childElements.any((e) => e.name.local == 'antipattern'), isFalse);
    });

    test('remove an absent particle is a conflict', () {
      final d = fixture();
      expect(
        () => editor.apply(d, const EditOp(
          verb: EditVerb.remove, targetKind: TargetKind.particle,
          target: 'trait', name: 'ghost',
        )),
        throwsA(isA<EditConflictException>()),
      );
    });

    test('rename rewrites the handle, body untouched', () {
      final d = fixture();
      editor.apply(d, const EditOp(
        verb: EditVerb.rename, targetKind: TargetKind.particle,
        target: 'trait', name: 'refined', newName: 'polished',
      ));
      final t = abstractOf(d).childElements.firstWhere((e) => e.name.local == 'trait');
      expect(t.getAttribute('name'), 'polished');
      expect(t.innerText, 'form matters');
    });

    test('rename onto an existing sibling handle is a conflict', () {
      final d = fixture();
      editor.apply(d, const EditOp(
        verb: EditVerb.add, targetKind: TargetKind.particle,
        target: 'trait', name: 'loving', content: 'x',
      ));
      expect(
        () => editor.apply(d, const EditOp(
          verb: EditVerb.rename, targetKind: TargetKind.particle,
          target: 'trait', name: 'refined', newName: 'loving',
        )),
        throwsA(isA<EditConflictException>()),
      );
    });
  });

  group('member-split guard (v1 single-file scope)', () {
    test('a realm reached only through xi:include is a conflict naming the member', () {
      final d = XmlDocument.parse(
        '<atom xmlns:xi="http://www.w3.org/2001/XInclude" v="1.0">'
        '<xi:include href="x_abstract.xml"/>'
        '</atom>',
      );
      expect(
        () => editor.apply(d, const EditOp(
          verb: EditVerb.add, targetKind: TargetKind.particle,
          target: 'trait', name: 'loving', content: 'x',
        )),
        throwsA(isA<EditConflictException>()),
      );
    });
  });
}
