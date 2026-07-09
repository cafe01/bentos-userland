import 'package:bentos_userland/src/manifest/atom_editor.dart';
import 'package:bentos_userland/src/manifest/edit_op.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

/// CONTRACT — [AtomEditor] applies a validated op to a FLAT atom DOM
/// (elements are direct children of `<atom>`, schema-blind), honouring the
/// arity guard and the member-split guard, raising [EditConflictException]
/// when a legal op meets an incompatible document. Pure DOM, zero IO.
void main() {
  const editor = AtomEditor();

  // A minimal flat atom in the shipped genome shape.
  XmlDocument fixture() => XmlDocument.parse(
        '<atom id="anamnesis.faculty" v="0.2">'
        '<telos>to remain one person</telos>'
        '<capacity name="recollection">gather yourself</capacity>'
        '<capacity name="inscription">lay yourself down</capacity>'
        '<principle name="north-star">advance BentOS</principle>'
        '</atom>',
      );

  Iterable<XmlElement> children(XmlDocument d, String tag) =>
      d.rootElement.childElements.where((e) => e.name.local == tag);

  group('add — appends a direct child of <atom>', () {
    test('a new named element lands under the root, handle set', () {
      final d = fixture();
      editor.apply(d, const EditOp(
        verb: EditVerb.add, targetKind: TargetKind.element,
        target: 'capacity', name: 'foresight', content: 'see ahead',
      ));
      final added = children(d, 'capacity')
          .where((e) => e.getAttribute('name') == 'foresight');
      expect(added, hasLength(1));
      expect(added.single.innerText, 'see ahead');
      // Appended last.
      expect(d.rootElement.childElements.last.getAttribute('name'), 'foresight');
    });

    test('any tag is legal — the vocabulary is open', () {
      final d = fixture();
      editor.apply(d, const EditOp(
        verb: EditVerb.add, targetKind: TargetKind.element,
        target: 'knowledge', name: 'k', content: 'understood',
      ));
      expect(children(d, 'knowledge'), hasLength(1));
    });

    test('adding a duplicate named element is a conflict', () {
      final d = fixture();
      expect(
        () => editor.apply(d, const EditOp(
          verb: EditVerb.add, targetKind: TargetKind.element,
          target: 'capacity', name: 'recollection', content: 'dup',
        )),
        throwsA(isA<EditConflictException>()),
      );
    });

    test('adding a duplicate bare element is a conflict (use set)', () {
      final d = fixture();
      expect(
        () => editor.apply(d, const EditOp(
          verb: EditVerb.add, targetKind: TargetKind.element,
          target: 'telos', content: 'dup',
        )),
        throwsA(isA<EditConflictException>()),
      );
    });
  });

  group('set — upsert: replace body if present, create if absent', () {
    test('set an existing named element\'s body, handle preserved', () {
      final d = fixture();
      editor.apply(d, const EditOp(
        verb: EditVerb.set, targetKind: TargetKind.element,
        target: 'capacity', name: 'recollection', content: 'new body',
      ));
      final el = children(d, 'capacity')
          .firstWhere((e) => e.getAttribute('name') == 'recollection');
      expect(el.innerText, 'new body');
    });

    test('set an existing bare element\'s body', () {
      final d = fixture();
      editor.apply(d, const EditOp(
        verb: EditVerb.set, targetKind: TargetKind.element,
        target: 'telos', content: 'new telos',
      ));
      expect(children(d, 'telos').single.innerText, 'new telos');
      expect(children(d, 'telos'), hasLength(1));
    });

    test('set an absent element creates it (upsert)', () {
      final d = fixture();
      editor.apply(d, const EditOp(
        verb: EditVerb.set, targetKind: TargetKind.element,
        target: 'principle', name: 'new-one', content: 'fresh',
      ));
      expect(
        children(d, 'principle')
            .where((e) => e.getAttribute('name') == 'new-one'),
        hasLength(1),
      );
    });

    test('set an atom attribute writes the root scalar, id untouched', () {
      final d = fixture();
      editor.apply(d, const EditOp(
        verb: EditVerb.set, targetKind: TargetKind.attribute,
        target: 'v', value: '0.3',
      ));
      expect(d.rootElement.getAttribute('v'), '0.3');
      expect(d.rootElement.getAttribute('id'), 'anamnesis.faculty');
    });
  });

  group('the arity guard — a dropped handle is exit-1, never corruption', () {
    test('handle-less set against a tag with named instances is a conflict', () {
      final d = fixture();
      expect(
        () => editor.apply(d, const EditOp(
          verb: EditVerb.set, targetKind: TargetKind.element,
          target: 'capacity', content: 'oops, forgot the handle',
        )),
        throwsA(isA<EditConflictException>()),
      );
      // Nothing was created beside the named ones.
      expect(children(d, 'capacity'), hasLength(2));
    });

    test('handle-less remove against a tag with named instances is a conflict', () {
      final d = fixture();
      expect(
        () => editor.apply(d, const EditOp(
          verb: EditVerb.remove, targetKind: TargetKind.element,
          target: 'capacity',
        )),
        throwsA(isA<EditConflictException>()),
      );
    });

    test('handle-less add of a tag with named instances is a conflict', () {
      final d = fixture();
      expect(
        () => editor.apply(d, const EditOp(
          verb: EditVerb.add, targetKind: TargetKind.element,
          target: 'capacity', content: 'bare beside named',
        )),
        throwsA(isA<EditConflictException>()),
      );
    });
  });

  group('remove / rename', () {
    test('remove detaches the named element', () {
      final d = fixture();
      editor.apply(d, const EditOp(
        verb: EditVerb.remove, targetKind: TargetKind.element,
        target: 'capacity', name: 'inscription',
      ));
      expect(
        children(d, 'capacity').map((e) => e.getAttribute('name')),
        ['recollection'],
      );
    });

    test('remove a bare element', () {
      final d = fixture();
      editor.apply(d, const EditOp(
        verb: EditVerb.remove, targetKind: TargetKind.element,
        target: 'telos',
      ));
      expect(children(d, 'telos'), isEmpty);
    });

    test('remove an absent element is a conflict', () {
      final d = fixture();
      expect(
        () => editor.apply(d, const EditOp(
          verb: EditVerb.remove, targetKind: TargetKind.element,
          target: 'capacity', name: 'ghost',
        )),
        throwsA(isA<EditConflictException>()),
      );
    });

    test('rename rewrites the handle, body untouched', () {
      final d = fixture();
      editor.apply(d, const EditOp(
        verb: EditVerb.rename, targetKind: TargetKind.element,
        target: 'capacity', name: 'recollection', newName: 'remembrance',
      ));
      final el = children(d, 'capacity')
          .firstWhere((e) => e.getAttribute('name') == 'remembrance');
      expect(el.innerText, 'gather yourself');
    });

    test('rename onto an existing sibling handle is a conflict', () {
      final d = fixture();
      expect(
        () => editor.apply(d, const EditOp(
          verb: EditVerb.rename, targetKind: TargetKind.element,
          target: 'capacity', name: 'recollection', newName: 'inscription',
        )),
        throwsA(isA<EditConflictException>()),
      );
    });

    test('rename an absent element is a conflict', () {
      final d = fixture();
      expect(
        () => editor.apply(d, const EditOp(
          verb: EditVerb.rename, targetKind: TargetKind.element,
          target: 'capacity', name: 'ghost', newName: 'x',
        )),
        throwsA(isA<EditConflictException>()),
      );
    });
  });

  group('member-split guard (v1 single-file scope)', () {
    test('an absent target beside an xi:include is a conflict naming the member route', () {
      final d = XmlDocument.parse(
        '<atom xmlns:xi="http://www.w3.org/2001/XInclude" id="x.faculty" v="1.0">'
        '<xi:include href="x_abstract.xml"/>'
        '</atom>',
      );
      expect(
        () => editor.apply(d, const EditOp(
          verb: EditVerb.add, targetKind: TargetKind.element,
          target: 'capacity', name: 'c', content: 'x',
        )),
        throwsA(isA<EditConflictException>()),
      );
    });

    test('a target literally present beside an xi:include is editable', () {
      final d = XmlDocument.parse(
        '<atom xmlns:xi="http://www.w3.org/2001/XInclude" id="x.faculty" v="1.0">'
        '<telos>t</telos>'
        '<xi:include href="x_abstract.xml"/>'
        '</atom>',
      );
      editor.apply(d, const EditOp(
        verb: EditVerb.set, targetKind: TargetKind.element,
        target: 'telos', content: 'new',
      ));
      expect(d.rootElement.getElement('telos')!.innerText, 'new');
    });
  });
}
