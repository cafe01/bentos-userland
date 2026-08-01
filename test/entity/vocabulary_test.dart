import 'package:bentos_userland/entity.dart';
import 'package:bentos_userland/src/entity/arming/arming.dart';
import 'package:bentos_userland/src/entity/commands/coordinate.dart';
import 'package:test/test.dart';

/// The design's own code — the encodings the ontology and the substrate meet
/// at. Green today, because none of it is construction's: how an action's noun
/// is written on a commit, how a coordinate is spelled at a shell, how a table
/// line survives being written by a program and read by a shell.
void main() {
  group('an action is named by what it deposits', () {
    test('the noun is written in structured form and read back', () {
      final message = Action.messageFor('tool-result');
      expect(Action.nameIn(message), 'tool-result');
      expect(message, startsWith('tool-result'), reason: 'the subject is the noun');
    });

    test('a commit made outside the ontology declares no action', () {
      expect(Action.nameIn('fix the typo\n'), isNull);
      expect(
        Action.nameIn('subject\n\nCo-authored-by: someone\n'),
        isNull,
        reason: 'an ordinary commit is not an error, it is simply not an act',
      );
    });

    test('the trailer wins over the subject, which is a human surface', () {
      expect(Action.nameIn('whatever prose\n\nBentos-Action: prompt\n'), 'prompt');
    });
  });

  group('the coordinate', () {
    test('is entity and instance', () {
      final c = Coordinate.parse('bentos.llm:s1');
      expect(c.entity, 'bentos.llm');
      expect(c.instance, 's1');
      expect(c.path, isNull);
    });

    test('carries a path for the verbs that read content', () {
      final c = Coordinate.parse('bentos.llm:s1:messages/1.json');
      expect(c.path, 'messages/1.json');
      expect(c.toString(), 'bentos.llm:s1:messages/1.json');
    });

    test('a bare name is not a coordinate — it names a class', () {
      expect(() => Coordinate.parse('bentos.llm'), throwsFormatException);
      expect(() => Coordinate.parse('bentos.llm:'), throwsFormatException);
    });
  });

  group('an arming line', () {
    test('round-trips through the wire form the shim reads', () {
      final r = Registration(
        id: 'r1',
        instance: '*',
        pattern: EventPattern.parse('prompt.landed'),
        command: ['llm-runner', '--verbose'],
      );
      final back = ArmingTables.decode(ArmingTables.encode(r), EventPhase.landed)!;
      expect(back.id, 'r1');
      expect(back.instance, '*');
      expect(back.pattern.action, 'prompt');
      expect(back.command, ['llm-runner', '--verbose']);
    });

    test('a blank or commented line is not a registration', () {
      expect(ArmingTables.decode('', EventPhase.landed), isNull);
      expect(ArmingTables.decode('   ', EventPhase.landed), isNull);
      expect(ArmingTables.decode('# disabled', EventPhase.landed), isNull);
    });

    test('a malformed line is refused rather than half-read', () {
      expect(ArmingTables.decode('r1\t*', EventPhase.landed), isNull);
    });
  });

  group('the commit value type', () {
    test('the null object name is what "must not exist" is spelled as', () {
      expect(Commit.zero.isZero, isTrue);
      expect(const Commit('abc123').isZero, isFalse);
    });

    test('two handles to one object are the same value', () {
      expect(const Commit('abc123'), const Commit('abc123'));
    });
  });
}
