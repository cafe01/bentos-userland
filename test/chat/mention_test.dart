import 'package:bentos_userland/src/chat/handle.dart';
import 'package:bentos_userland/src/chat/mention.dart';
import 'package:test/test.dart';

void main() {
  group('MentionScanner', () {
    final me = const Handle('alfred', '');
    final scanner = MentionScanner(me);

    test('a plain sentence is not a mention', () {
      expect(scanner.mentions('chat is green end to end'), isFalse);
    });

    test('naming the handle mentions', () {
      expect(scanner.mentions('alfred, status?'), isFalse);
      expect(scanner.mentions('@alfred, status?'), isTrue);
    });

    test('matching is case-insensitive', () {
      expect(scanner.mentions('@Alfred are you there'), isTrue);
    });

    test('naming someone else does not mention', () {
      expect(scanner.mentions('@cafe01 status?'), isFalse);
    });

    test('the all word mentions everyone', () {
      expect(scanner.mentions('@all raising the install gate'), isTrue);
    });

    test('a custom all word replaces the default', () {
      final s = MentionScanner(me, allWord: 'everyone');
      expect(s.mentions('@all hi'), isFalse);
      expect(s.mentions('@everyone hi'), isTrue);
    });
  });
}
