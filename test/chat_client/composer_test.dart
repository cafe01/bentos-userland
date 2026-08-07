import 'package:bentos_userland/src/chat_client/composer.dart';
import 'package:test/test.dart';

void main() {
  group('Composer', () {
    test('inserts at the cursor and advances it', () {
      final c = Composer();
      c.insert('hi');
      expect(c.text, 'hi');
      expect(c.cursor, 2);
    });

    test('backspace deletes one grapheme cluster before the cursor', () {
      final c = Composer();
      c.insert('👨‍👩‍👧‍👦x'); // family emoji (one cluster) + a letter
      expect(c.length, 2);

      c.backspace();
      expect(c.text, '👨‍👩‍👧‍👦');
      expect(c.length, 1);

      c.backspace();
      expect(c.text, '');
      expect(c.length, 0);
    });

    test('backspace at the start of the line is a no-op', () {
      final c = Composer();
      c.insert('hi');
      c.moveToStart();
      c.backspace();
      expect(c.text, 'hi');
    });

    test('deleteForward removes the cluster under the cursor', () {
      final c = Composer();
      c.insert('hi');
      c.moveToStart();
      c.deleteForward();
      expect(c.text, 'i');
    });

    test('insert in the middle splices, never appends', () {
      final c = Composer();
      c.insert('hlo');
      c.moveLeft();
      c.moveLeft();
      c.insert('el');
      expect(c.text, 'hello');
    });

    test('submit sends the buffer, clears it, and remembers it', () {
      final c = Composer();
      c.insert('raising the install gate');
      final sent = c.submit();

      expect(sent, 'raising the install gate');
      expect(c.text, '');
      expect(c.sentHistory, ['raising the install gate']);
    });

    test('submit of a whitespace-only buffer sends nothing and keeps the buffer', () {
      final c = Composer();
      c.insert('   ');
      final sent = c.submit();

      expect(sent, isNull);
      expect(c.text, '   ');
      expect(c.sentHistory, isEmpty);
    });

    test('historyPrevious steps to older sent lines without losing the draft', () {
      final c = Composer(sentHistory: ['first', 'second']);
      c.insert('typing');

      c.historyPrevious();
      expect(c.text, 'second');
      c.historyPrevious();
      expect(c.text, 'first');
      c.historyPrevious(); // at the oldest, stays
      expect(c.text, 'first');

      c.historyNext();
      expect(c.text, 'second');
      c.historyNext(); // past the newest: back to the draft
      expect(c.text, 'typing');
      expect(c.isBrowsingHistory, isFalse);
    });

    test('typing while browsing history exits history and edits in place', () {
      final c = Composer(sentHistory: ['old line']);
      c.historyPrevious();
      expect(c.text, 'old line');

      c.insert('!');
      expect(c.isBrowsingHistory, isFalse);
      expect(c.text, 'old line!');
    });

    test('clear empties the buffer without touching sent history', () {
      final c = Composer();
      c.insert('draft');
      c.clear();
      expect(c.text, '');
      expect(c.sentHistory, isEmpty);
    });
  });
}
