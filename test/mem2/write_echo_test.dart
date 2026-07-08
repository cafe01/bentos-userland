import 'package:bentos_userland/src/mem2/model/attention.dart';
import 'package:bentos_userland/src/mem2/model/mem_page.dart';
import 'package:bentos_userland/src/mem2/write_echo.dart';
import 'package:bentos_userland/src/place/place.dart';
import 'package:bentos_userland/src/testing/run_in_memory_fs.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('WriteEcho', () {
    MemHabitat habitat() {
      final hab = MemHabitat();
      hab.place('/hq');
      hab.place('/hq/cto');
      return hab;
    }

    test('remembered echoes the landed post-state', () {
      runInMemoryFs((fs) {
        habitat();
        final vantage = Place('/hq/cto');
        final page = memPage('agency/spawn',
            type: MemType.procedural, attention: '0.6', tags: ['reflex'], origin: vantage);
        final echo = WriteEcho(vantage).remembered(page, created: true);
        expect(echo, contains('remembered  agency/spawn  (procedural · a:0.6)'));
        expect(echo, contains('#reflex'));
        expect(echo, contains('created now'));
      });
    });

    test('a write landing off-vantage names its @place', () {
      runInMemoryFs((fs) {
        habitat();
        final vantage = Place('/hq/cto');
        final ancestor = Place('/hq');
        final page = memPage('founders', origin: ancestor);
        final echo = WriteEcho(vantage).remembered(page, created: false);
        expect(echo, contains('@${ancestor.name}'));
        expect(echo, contains('modified now'));
      });
    });

    test('a single refocus echoes on one line', () {
      runInMemoryFs((fs) {
        habitat();
        final vantage = Place('/hq/cto');
        final page = memPage('native-turn-front', origin: vantage);
        final echo = WriteEcho(vantage).refocused([
          RefocusChange(page, Attention.parse('0.8'), Attention.parse('1.0')),
        ]);
        expect(echo, contains('refocused  native-turn-front  0.8 → 1.0'));
      });
    });

    test('a bulk refocus echoes the per-page old → new list with clamps marked', () {
      runInMemoryFs((fs) {
        habitat();
        final vantage = Place('/hq/cto');
        final a = memPage('brain-front', tags: ['brain'], origin: vantage);
        final b = memPage('shadow-defect', tags: ['brain'], origin: vantage);
        final echo = WriteEcho(vantage).refocused([
          RefocusChange(a, Attention.parse('0.8'), Attention.parse('0.4')),
          RefocusChange(b, Attention.parse('0.3'), Attention.parse('0.0'), clamped: true),
        ], selector: 'tag:brain', by: '-0.4');
        expect(echo, contains('refocused 2 pages  (tag:brain)  --by -0.4'));
        expect(echo, contains('0.8 → 0.4  brain-front'));
        expect(echo, contains('0.3 → 0.0  shadow-defect'));
        expect(echo, contains('(clamped)'));
      });
    });

    test('forgot names each released page and its last attention', () {
      runInMemoryFs((fs) {
        habitat();
        final vantage = Place('/hq/cto');
        final echo = WriteEcho(vantage).forgot([
          memPage('front-a', type: MemType.prospective, attention: '1.0', origin: vantage),
          memPage('front-b', type: MemType.prospective, attention: '0.7', origin: vantage),
        ]);
        expect(echo, contains('forgot  front-a  (prospective · was a:1.0)  — content deleted'));
        expect(echo, contains('forgot  front-b  (prospective · was a:0.7)  — content deleted'));
      });
    });
  });
}
