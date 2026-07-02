import 'package:bentos_userland/src/mem2/relative_age.dart';
import 'package:test/test.dart';

void main() {
  group('RelativeAge — the freshness signal', () {
    final clock = DateTime.utc(2026, 7, 2, 12);
    final age = RelativeAge(() => clock);

    test('renders sub-minute, minutes, hours, days', () {
      expect(age.of(clock.subtract(const Duration(seconds: 30))), '30s');
      expect(age.of(clock.subtract(const Duration(minutes: 5))), '5m');
      expect(age.of(clock.subtract(const Duration(hours: 2))), '2h');
      expect(age.of(clock.subtract(const Duration(days: 5))), '5d');
    });

    test('boundaries round sanely', () {
      expect(age.of(clock.subtract(const Duration(seconds: 59))), '59s');
      expect(age.of(clock.subtract(const Duration(minutes: 59))), '59m');
      expect(age.of(clock.subtract(const Duration(hours: 23))), '23h');
    });

    test('a future timestamp collapses to now, does not crash', () {
      expect(age.of(clock.add(const Duration(hours: 3))), 'now');
      expect(age.of(clock), 'now');
    });
  });
}
