import 'package:bentos_userland/src/mem2/band.dart';
import 'package:test/test.dart';

void main() {
  group('Band — the attention heatmap', () {
    test('each shortcut maps to its inclusive range', () {
      expect((Band.hot.minTenths, Band.hot.maxTenths), (10, 10));
      expect((Band.warm.minTenths, Band.warm.maxTenths), (7, 9));
      expect((Band.cool.minTenths, Band.cool.maxTenths), (4, 6));
      expect((Band.cold.minTenths, Band.cold.maxTenths), (1, 3));
    });

    test('the four bands plus 0.0 partition the scale — every notch once', () {
      for (var notch = 1; notch <= 10; notch++) {
        final owners = Band.values.where(
            (b) => notch >= b.minTenths && notch <= b.maxTenths);
        expect(owners, hasLength(1), reason: 'notch $notch in exactly one band');
      }
      expect(
        Band.values.where((b) => 0 >= b.minTenths && 0 <= b.maxTenths),
        isEmpty,
        reason: '0.0 is the vanishing point, in no band',
      );
    });

    test('parse resolves by name; an out-of-table band errors', () {
      expect(Band.parse('warm'), Band.warm);
      expect(() => Band.parse('tepid'), throwsFormatException);
    });
  });
}
