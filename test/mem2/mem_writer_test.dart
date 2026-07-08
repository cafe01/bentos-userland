import 'dart:io';

import 'package:bentos_userland/src/mem2/model/attention.dart';
import 'package:bentos_userland/src/mem2/model/mem_page.dart';
import 'package:bentos_userland/src/mem2/model/mem_writer.dart';
import 'package:bentos_userland/src/testing/run_in_memory_fs.dart';
import 'package:test/test.dart';

void main() {
  group('MemWriter — dates and the attention-only path', () {
    test('first body write stamps created and modified', () {
      runInMemoryFs((fs) {
        var clock = DateTime.utc(2026, 7, 2, 10);
        final writer = MemWriter(() => clock);
        final file = File('/store/agency/spawn.md');
        final page = writer.writeBody(file, 'agency/spawn',
            type: MemType.procedural, attention: Attention.parse('0.7'), body: 'how to spawn');
        expect(page.fields.created, DateTime.utc(2026, 7, 2, 10));
        expect(page.fields.modified, DateTime.utc(2026, 7, 2, 10));
      });
    });

    test('replace keeps created, refreshes modified', () {
      runInMemoryFs((fs) {
        var clock = DateTime.utc(2026, 7, 2, 10);
        final writer = MemWriter(() => clock);
        final file = File('/store/agency/spawn.md');
        writer.writeBody(file, 'agency/spawn',
            type: MemType.procedural, attention: Attention.parse('0.7'), body: 'v1');
        clock = DateTime.utc(2026, 7, 3, 12);
        final v2 = writer.writeBody(file, 'agency/spawn',
            type: MemType.procedural, attention: Attention.parse('0.7'), body: 'v2');
        expect(v2.fields.created, DateTime.utc(2026, 7, 2, 10), reason: 'created stamped once');
        expect(v2.fields.modified, DateTime.utc(2026, 7, 3, 12), reason: 'modified tracks body');
        expect(v2.body, 'v2');
      });
    });

    test('refocus rewrites attention leaving body bytes and modified identical', () {
      runInMemoryFs((fs) {
        var clock = DateTime.utc(2026, 7, 2, 10);
        final writer = MemWriter(() => clock);
        final file = File('/store/agency/spawn.md');
        writer.writeBody(file, 'agency/spawn',
            type: MemType.procedural, attention: Attention.parse('0.7'), body: 'the body');
        final before = file.readAsStringSync();
        clock = DateTime.utc(2099, 1, 1); // advancing the clock must not leak in

        writer.refocus(file, Attention.parse('0.4'));
        final after = MemPage.parse('agency/spawn', file.readAsStringSync());

        expect(after.fields.attention, Attention.parse('0.4'));
        expect(after.body, 'the body', reason: 'body byte-identical');
        expect(after.fields.modified, DateTime.utc(2026, 7, 2, 10), reason: 'modified untouched');
        expect(file.readAsStringSync(), before.replaceFirst('attention: 0.7', 'attention: 0.4'),
            reason: 'only the attention line moved');
      });
    });
  });
}
