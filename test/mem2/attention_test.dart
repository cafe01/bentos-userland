import 'package:bentos_userland/src/mem2/model/attention.dart';
import 'package:test/test.dart';

void main() {
  group('Attention — the notched dial', () {
    test('parses every notch 0.0–1.0 and renders back exactly', () {
      for (var t = 0; t <= 10; t++) {
        final decimal = t == 10 ? '1.0' : '0.$t';
        expect(Attention.parse(decimal).render(), decimal, reason: 'notch $t round-trips');
      }
    });

    test('rejects off-notch input', () {
      for (final bad in ['0.75', '1.1', '-0.1', '2.0', '0.55', 'x']) {
        expect(() => Attention.parse(bad), throwsFormatException, reason: '"$bad" is off-notch');
      }
    });

    test('ofTenths rejects out-of-range', () {
      expect(() => Attention.ofTenths(-1), throwsRangeError);
      expect(() => Attention.ofTenths(11), throwsRangeError);
    });

    test('ordering and equality are integral', () {
      expect(Attention.parse('0.7') == Attention.parse('0.7'), isTrue);
      expect(Attention.parse('0.7').compareTo(Attention.parse('0.9')), lessThan(0));
      expect(Attention.parse('1.0').compareTo(Attention.parse('0.3')), greaterThan(0));
    });

    test('adjust saturates at both rails and reports the clamp', () {
      expect(Attention.parse('0.7').adjust(-3), (Attention.parse('0.4'), false));
      final (lo, loClamped) = Attention.parse('0.2').adjust(-5);
      expect(lo.render(), '0.0');
      expect(loClamped, isTrue);
      final (hi, hiClamped) = Attention.parse('0.9').adjust(4);
      expect(hi.render(), '1.0');
      expect(hiClamped, isTrue);
    });
  });
}
