import 'package:bentos_userland/src/manifest/edit_op.dart';
import 'package:test/test.dart';

/// CONTRACT — the git grammar `<verb> <selector> [handles…]` parses into the
/// right [EditOp], and every malformed/illegal shape is a precise
/// [EditUsageException]. Schema-blind: element tags are open, `@x` is an
/// attribute; this layer sees only argv+stdin, never a file or DOM.
void main() {
  const parser = EditOpParser();

  group('well-formed ops bind argv + stdin correctly', () {
    test('add <tag> <name> with body on stdin', () {
      final op = parser.parse(['add', 'capacity', 'recollection'], stdinPresent: true);
      expect(op.verb, EditVerb.add);
      expect(op.targetKind, TargetKind.element);
      expect(op.target, 'capacity');
      expect(op.name, 'recollection');
    });

    test('set <tag> <name> replaces body from stdin', () {
      final op = parser.parse(['set', 'capacity', 'recollection'], stdinPresent: true);
      expect(op.verb, EditVerb.set);
      expect(op.name, 'recollection');
    });

    test('set <tag> without handle — bare element, body on stdin', () {
      final op = parser.parse(['set', 'telos'], stdinPresent: true);
      expect(op.verb, EditVerb.set);
      expect(op.target, 'telos');
      expect(op.name, isNull);
    });

    test('add of a bare tag is legal syntax (DOM guards the arity)', () {
      final op = parser.parse(['add', 'telos'], stdinPresent: true);
      expect(op.name, isNull);
    });

    test('the tag vocabulary is open — any string parses', () {
      final op = parser.parse(['add', 'frobnicate', 'x'], stdinPresent: true);
      expect(op.target, 'frobnicate');
    });

    test('remove <tag> <name>, no stdin', () {
      final op = parser.parse(['remove', 'capacity', 'recollection'], stdinPresent: false);
      expect(op.verb, EditVerb.remove);
      expect(op.target, 'capacity');
      expect(op.name, 'recollection');
    });

    test('remove <tag> without handle — bare element', () {
      final op = parser.parse(['remove', 'telos'], stdinPresent: false);
      expect(op.name, isNull);
    });

    test('rename <tag> <name> <newName>, no stdin', () {
      final op = parser.parse(
          ['rename', 'capacity', 'recollection', 'remembrance'],
          stdinPresent: false);
      expect(op.verb, EditVerb.rename);
      expect(op.name, 'recollection');
      expect(op.newName, 'remembrance');
    });

    test('set @v <value> — attribute, value on argv, no stdin', () {
      final op = parser.parse(['set', '@v', '0.3'], stdinPresent: false);
      expect(op.verb, EditVerb.set);
      expect(op.targetKind, TargetKind.attribute);
      expect(op.target, 'v');
      expect(op.value, '0.3');
    });
  });

  group('malformed / illegal — each a EditUsageException', () {
    test('no verb at all', () {
      expect(() => parser.parse([], stdinPresent: false),
          throwsA(isA<EditUsageException>()));
    });

    test('unknown verb', () {
      expect(() => parser.parse(['frob', 'capacity', 'x'], stdinPresent: true),
          throwsA(isA<EditUsageException>()));
    });

    test('verb without selector', () {
      expect(() => parser.parse(['add'], stdinPresent: true),
          throwsA(isA<EditUsageException>()));
    });

    test('bare @ selector', () {
      expect(() => parser.parse(['set', '@', '0.3'], stdinPresent: false),
          throwsA(isA<EditUsageException>()));
    });

    test('add on an attribute is illegal', () {
      expect(() => parser.parse(['add', '@v', '0.3'], stdinPresent: false),
          throwsA(isA<EditUsageException>()));
    });

    test('remove on an attribute is illegal', () {
      expect(() => parser.parse(['remove', '@v'], stdinPresent: false),
          throwsA(isA<EditUsageException>()));
    });

    test('rename on an attribute is deferred/illegal', () {
      expect(() => parser.parse(['rename', '@v', '0.2', '0.3'], stdinPresent: false),
          throwsA(isA<EditUsageException>()));
    });

    test('attribute set without a value', () {
      expect(() => parser.parse(['set', '@v'], stdinPresent: false),
          throwsA(isA<EditUsageException>()));
    });

    test('attribute set with extra arguments', () {
      expect(() => parser.parse(['set', '@v', '0.3', 'extra'], stdinPresent: false),
          throwsA(isA<EditUsageException>()));
    });

    test('attribute set must not read stdin', () {
      expect(() => parser.parse(['set', '@v', '0.3'], stdinPresent: true),
          throwsA(isA<EditUsageException>()));
    });

    test('element add/set with no stdin body is illegal', () {
      expect(() => parser.parse(['add', 'capacity', 'x'], stdinPresent: false),
          throwsA(isA<EditUsageException>()));
      expect(() => parser.parse(['set', 'telos'], stdinPresent: false),
          throwsA(isA<EditUsageException>()));
    });

    test('remove fed a stdin body is illegal', () {
      expect(() => parser.parse(['remove', 'capacity', 'x'], stdinPresent: true),
          throwsA(isA<EditUsageException>()));
    });

    test('rename missing the new name', () {
      expect(() => parser.parse(['rename', 'capacity', 'recollection'], stdinPresent: false),
          throwsA(isA<EditUsageException>()));
    });

    test('rename fed a stdin body is illegal', () {
      expect(
          () => parser.parse(['rename', 'capacity', 'a', 'b'], stdinPresent: true),
          throwsA(isA<EditUsageException>()));
    });

    test('too many positionals for add/set/remove/rename', () {
      expect(() => parser.parse(['add', 'capacity', 'a', 'b'], stdinPresent: true),
          throwsA(isA<EditUsageException>()));
      expect(() => parser.parse(['remove', 'capacity', 'a', 'b'], stdinPresent: false),
          throwsA(isA<EditUsageException>()));
      expect(() => parser.parse(['rename', 'capacity', 'a', 'b', 'c'], stdinPresent: false),
          throwsA(isA<EditUsageException>()));
    });
  });
}
