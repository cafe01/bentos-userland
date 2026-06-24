import 'package:bentos_userland/src/manifest/edit_op.dart';
import 'package:test/test.dart';

/// CONTRACT — the fused-flag grammar `--<verb>-<target>` parses into the right
/// [EditOp], and every malformed/illegal shape is a precise [EditUsageException].
/// This is the SYNTAX→intent layer; it sees the vocabulary, never a file.
void main() {
  const parser = EditOpParser();

  group('well-formed ops bind argv + stdin correctly', () {
    test('--add-trait <name> with body on stdin', () {
      final op = parser.parse(['--add-trait', 'refined'], stdinPresent: true);
      expect(op.verb, EditVerb.add);
      expect(op.targetKind, TargetKind.particle);
      expect(op.target, 'trait');
      expect(op.name, 'refined');
    });

    test('--set-trait <name> replaces body from stdin', () {
      final op = parser.parse(['--set-trait', 'refined'], stdinPresent: true);
      expect(op.verb, EditVerb.set);
      expect(op.name, 'refined');
    });

    test('--remove-antipattern <name>, no stdin', () {
      final op = parser.parse(['--remove-antipattern', 'voice-drift'], stdinPresent: false);
      expect(op.verb, EditVerb.remove);
      expect(op.target, 'antipattern');
      expect(op.name, 'voice-drift');
    });

    test('--rename-trait <name> <newName>, no stdin', () {
      final op = parser.parse(['--rename-trait', 'refined', 'polished'], stdinPresent: false);
      expect(op.verb, EditVerb.rename);
      expect(op.name, 'refined');
      expect(op.newName, 'polished');
    });

    test('--set-v <value> — attribute, value on argv, no stdin', () {
      final op = parser.parse(['--set-v', '0.3'], stdinPresent: false);
      expect(op.verb, EditVerb.set);
      expect(op.targetKind, TargetKind.attribute);
      expect(op.target, 'v');
      expect(op.value, '0.3');
    });

    test('singleton --set-essence — body on stdin, NO name', () {
      final op = parser.parse(['--set-essence'], stdinPresent: true);
      expect(op.target, 'essence');
      expect(op.name, isNull);
    });

    test('singleton add≡set — --add-essence is accepted as create-or-replace', () {
      final op = parser.parse(['--add-essence'], stdinPresent: true);
      expect(op.target, 'essence');
      expect(op.name, isNull);
    });
  });

  group('malformed / illegal — each a EditUsageException', () {
    test('unknown verb', () {
      expect(() => parser.parse(['--frob-trait', 'x'], stdinPresent: true),
          throwsA(isA<EditUsageException>()));
    });

    test('unknown particle', () {
      expect(() => parser.parse(['--add-frobnicate', 'x'], stdinPresent: true),
          throwsA(isA<EditUsageException>()));
    });

    test('v2-deferred relation particle is rejected with a scope message', () {
      expect(() => parser.parse(['--add-requires', 'x.faculty'], stdinPresent: false),
          throwsA(isA<EditUsageException>()));
      expect(() => parser.parse(['--add-attracts', 'x'], stdinPresent: false),
          throwsA(isA<EditUsageException>()));
    });

    test('no op flag at all', () {
      expect(() => parser.parse(['refined'], stdinPresent: true),
          throwsA(isA<EditUsageException>()));
    });

    test('more than one op flag', () {
      expect(() => parser.parse(['--add-trait', 'a', '--remove-trait', 'b'], stdinPresent: true),
          throwsA(isA<EditUsageException>()));
    });

    test('named particle without a name', () {
      expect(() => parser.parse(['--add-trait'], stdinPresent: true),
          throwsA(isA<EditUsageException>()));
    });

    test('singleton given a name', () {
      expect(() => parser.parse(['--set-essence', 'oops'], stdinPresent: true),
          throwsA(isA<EditUsageException>()));
    });

    test('rename on an attribute is illegal', () {
      expect(() => parser.parse(['--rename-v', '0.2', '0.3'], stdinPresent: false),
          throwsA(isA<EditUsageException>()));
    });

    test('rename on a singleton is illegal (no handle)', () {
      expect(() => parser.parse(['--rename-essence', 'x'], stdinPresent: false),
          throwsA(isA<EditUsageException>()));
    });

    test('rename missing the new name', () {
      expect(() => parser.parse(['--rename-trait', 'refined'], stdinPresent: false),
          throwsA(isA<EditUsageException>()));
    });

    test('remove fed a stdin body is illegal', () {
      expect(() => parser.parse(['--remove-trait', 'refined'], stdinPresent: true),
          throwsA(isA<EditUsageException>()));
    });

    test('attribute set must not read stdin', () {
      expect(() => parser.parse(['--set-v', '0.3'], stdinPresent: true),
          throwsA(isA<EditUsageException>()));
    });

    test('particle set/add with no stdin body is illegal', () {
      expect(() => parser.parse(['--add-trait', 'refined'], stdinPresent: false),
          throwsA(isA<EditUsageException>()));
    });
  });
}
