import 'package:bentos_userland/src/chat_client/activity.dart';
import 'package:test/test.dart';

void main() {
  group('Activity', () {
    test('starts quiet', () {
      final a = Activity();
      expect(a.isQuiet, isTrue);
      expect(a.count, 0);
    });

    test('speech raises to speech and counts', () {
      final a = Activity();
      a.noteSpoken();
      a.noteSpoken();

      expect(a.level, ActivityLevel.speech);
      expect(a.count, 2);
    });

    test('a mention outranks speech', () {
      final a = Activity();
      a.noteSpoken();
      a.noteMention();

      expect(a.level, ActivityLevel.mention);
      expect(a.count, 2);
    });

    test('speech after a mention does not demote it', () {
      final a = Activity();
      a.noteMention();
      a.noteSpoken();

      expect(a.level, ActivityLevel.mention);
      expect(a.count, 2);
    });

    test('clear silences the room', () {
      final a = Activity();
      a.noteMention();
      a.clear();

      expect(a.isQuiet, isTrue);
      expect(a.count, 0);
    });
  });
}
