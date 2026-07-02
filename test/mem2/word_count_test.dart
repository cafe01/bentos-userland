import 'package:bentos_userland/src/mem2/word_count.dart';
import 'package:test/test.dart';

void main() {
  group('WordCount — the size hint', () {
    test('counts whitespace-delimited words', () {
      expect(const WordCount().count('one two  three\nfour'), 4);
    });

    test('below threshold → no hint', () {
      expect(const WordCount(threshold: 5).hint('one two three'), isNull);
    });

    test('at or above threshold → [Nw]', () {
      expect(const WordCount(threshold: 3).hint('one two three'), '[3w]');
      expect(const WordCount(threshold: 3).hint('one two three four'), '[4w]');
    });

    test('empty body → no hint', () {
      expect(const WordCount(threshold: 1).hint('   '), isNull);
      expect(const WordCount().count(''), 0);
    });
  });
}
