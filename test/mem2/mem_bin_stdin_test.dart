/// Process-boundary test: `bin/mem.dart` must drain a real OS pipe on stdin.
/// Everything else in mem2 is exercised through [MemRunner] with an injected
/// `stdinContent` (hermetic); this is the one seam that only a real
/// `Process` + real pipe can prove — a unit test that stubs stdin can't
/// catch a regression in the drain itself.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('mem remember reads the body from a real piped stdin', () async {
    final packageRoot = Directory.current.path;
    final place = Directory.systemTemp.createTempSync('mem-stdin-test-');
    addTearDown(() => place.deleteSync(recursive: true));
    Directory(p.join(place.path, '.place')).createSync();

    final proc = await Process.start(
      'dart',
      [
        'run', p.join(packageRoot, 'bin', 'mem.dart'),
        'remember',
        '-b', 'testbank',
        '-p', place.path,
        '-t', 'semantic',
        '-A', '0.5',
        '--gist', 'stub gist',
        'domain/topic',
      ],
      workingDirectory: packageRoot,
    );
    proc.stdin.add(utf8.encode('the body from a real pipe\n'));
    await proc.stdin.close();
    final stderrText = await proc.stderr.transform(utf8.decoder).join();
    final code = await proc.exitCode;

    expect(code, 0, reason: 'stderr: $stderrText');

    final landed = File(p.join(place.path, 'testbank.mem', 'domain', 'topic.md'));
    expect(landed.existsSync(), isTrue);
    expect(landed.readAsStringSync(), contains('the body from a real pipe'));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('a read verb never waits on a stdin pipe that stays open', () async {
    final packageRoot = Directory.current.path;
    final place = Directory.systemTemp.createTempSync('mem-stdin-open-');
    addTearDown(() => place.deleteSync(recursive: true));
    Directory(p.join(place.path, '.place')).createSync();

    // The pipe is deliberately left open: an inherited stdin that never sees
    // EOF is the ordinary case under an agent harness, and draining it up
    // front hung every verb, reads included.
    final proc = await Process.start(
      'dart',
      [
        'run', p.join(packageRoot, 'bin', 'mem.dart'),
        'survey',
        '-b', 'testbank',
        '-p', place.path,
      ],
      workingDirectory: packageRoot,
    );
    final code = await proc.exitCode.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        proc.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    await proc.stdin.close();

    expect(code, isNot(-1), reason: 'survey blocked on an open stdin');
  }, timeout: const Timeout(Duration(seconds: 120)));
}
