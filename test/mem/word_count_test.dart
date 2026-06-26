import 'package:bentos_userland/src/mem/word_count.dart';
import 'package:test/test.dart';

void main() {
  group('WordCount.count', () {
    const wc = WordCount(threshold: 5);

    test('counts whitespace-delimited words', () {
      expect(wc.count('one two three four five six'), 6);
    });

    test('multiple spaces/tabs between words count as one separator', () {
      expect(wc.count('one  two\tthree'), 3);
    });

    test('leading and trailing whitespace ignored', () {
      expect(wc.count('  one two  '), 2);
    });

    test('empty string is zero words', () {
      expect(wc.count(''), 0);
    });
  });

  group('WordCount.hint', () {
    const wc = WordCount(threshold: 5);

    test('below threshold returns null', () {
      expect(wc.hint('one two three four'), isNull); // 4 < 5
    });

    test('at threshold returns [Nw]', () {
      expect(wc.hint('one two three four five'), '[5w]');
    });

    test('above threshold returns [Nw]', () {
      expect(wc.hint('one two three four five six'), '[6w]');
    });

    test('empty body returns null', () {
      expect(wc.hint(''), isNull);
    });
  });

  group('WordCount default threshold', () {
    const wc = WordCount();

    test('default threshold is 120', () {
      expect(wc.threshold, 120);
    });

    test('body of 119 words returns null', () {
      final body = List.generate(119, (i) => 'word').join(' ');
      expect(wc.hint(body), isNull);
    });

    test('body of 120 words returns hint', () {
      final body = List.generate(120, (i) => 'word').join(' ');
      expect(wc.hint(body), '[120w]');
    });
  });
}
