import 'package:bentos_userland/src/mem/attention.dart';
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

    test('the double factory rounds to the nearest notch and rejects off-scale', () {
      expect(Attention(0.7).render(), '0.7');
      expect(Attention(0.7000000000000001).render(), '0.7', reason: 'float noise rounds away');
      expect(() => Attention(-0.1), throwsRangeError);
      expect(() => Attention(1.1), throwsRangeError);
    });

    test('value is the decimal round-trip of tenths', () {
      expect(Attention.parse('0.7').value, 0.7);
      expect(Attention.parse('1.0').value, 1.0);
    });

    test('band maps each notch to its heatmap position', () {
      expect(Attention.parse('1.0').band, Band.hot);
      expect(Attention.parse('0.7').band, Band.warm);
      expect(Attention.parse('0.9').band, Band.warm);
      expect(Attention.parse('0.4').band, Band.cool);
      expect(Attention.parse('0.6').band, Band.cool);
      expect(Attention.parse('0.1').band, Band.cold);
      expect(Attention.parse('0.3').band, Band.cold);
    });

    test('0.0 carries no band', () {
      expect(() => Attention.parse('0.0').band, throwsStateError);
    });

    test('ordering and equality are integral', () {
      expect(Attention.parse('0.7') == Attention.parse('0.7'), isTrue);
      expect(Attention.parse('0.7').compareTo(Attention.parse('0.9')), lessThan(0));
      expect(Attention.parse('1.0').compareTo(Attention.parse('0.3')), greaterThan(0));
    });

    test('attention accepts the wider on-disk grammar without a FormatException', () {
      for (final form in ['.7', '0.70', '"0.7"', ' 0.7 ']) {
        expect(Attention.parse(form), Attention.parse('0.7'), reason: 'form: $form');
      }
      expect(Attention.parse('1'), Attention.parse('1.0'));
      expect(Attention.parse('0'), Attention.parse('0.0'));
    });
  });

  group('Band', () {
    test('parses by name', () {
      expect(Band.parse('warm'), Band.warm);
    });

    test('rejects an out-of-table name', () {
      expect(() => Band.parse('lukewarm'), throwsFormatException);
    });
  });
}
