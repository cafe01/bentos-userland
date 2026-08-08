import 'dart:io';

import 'package:bentos_userland/src/mem2/model/mem_page.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The one witness in this suite that runs against the real filesystem
/// rather than [runInMemoryFs]: an in-memory fixture cannot violate a
/// cross-process guard it never implements, so a green there would be a
/// green about nothing. Real `dart` subprocesses race on one real page —
/// each deriving its next write from what it actually read, the only shape
/// where a lost update is visible at all — and the claim is that
/// [MemWriter]'s per-page lock makes their writes land whole.
void main() {
  test('N processes racing a read-modify-write on one page lose nothing', () async {
    final dir = Directory.systemTemp.createTempSync('mem_writer_serialization_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File(p.join(dir.path, 'counter.md'));
    final worker = p.join(Directory.current.path, 'test', 'mem2', 'fixtures',
        'concurrent_increment_worker.dart');

    const processes = 6;
    const incrementsEach = 10;

    final results = await Future.wait([
      for (var i = 0; i < processes; i++)
        Process.run('dart', ['run', worker, file.path, '$incrementsEach']),
    ]);
    for (final r in results) {
      expect(r.exitCode, 0, reason: 'worker stderr: ${r.stderr}');
    }

    final finalCount = int.parse(MemPage.parse('counter', file.readAsStringSync()).body.trim());
    expect(finalCount, processes * incrementsEach,
        reason: 'every increment from every process must land — a lower count is a lost update');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
