/// End-to-end test of the real binary actually writing. Everything else in
/// mem2 stubs the gist seam, so the whole production write path — spawn `llm`,
/// read its pipes, land the page — was never exercised by a real process, and
/// a silent no-op (exit 0, nothing printed, nothing written) slipped through
/// green tests. Here `llm` is a fake on PATH and the page is checked on disk.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory sandbox;
  late Directory place;
  late Map<String, String> env;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('mem-write-e2e-');
    place = Directory(p.join(sandbox.path, 'place'))..createSync();
    Directory(p.join(place.path, '.place')).createSync();

    final fakeLlm = File(p.join(sandbox.path, 'llm'));
    fakeLlm.writeAsStringSync('#!/bin/sh\ncat > /dev/null\necho "the derived gist"\n');
    Process.runSync('chmod', ['+x', fakeLlm.path]);

    env = {'PATH': '${sandbox.path}:${Platform.environment['PATH']}'};
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  List<String> args(String topic) => [
        'run', p.join(Directory.current.path, 'bin', 'mem.dart'),
        'remember',
        '-b', 'testbank',
        '-p', place.path,
        '-t', 'semantic',
        '-A', '0.5',
        topic,
      ];

  File landed(String topic) =>
      File(p.join(place.path, 'testbank.mem', '$topic.md'));

  test('--file: the page lands on disk, gist derived through a real llm spawn',
      () async {
    final body = File(p.join(sandbox.path, 'body.md'));
    body.writeAsStringSync('# T\n\nthe body from a file.\n');

    final res = await Process.run(
      'dart',
      [...args('domain/from-file'), '-f', body.path],
      workingDirectory: Directory.current.path,
      environment: env,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    expect(res.exitCode, 0, reason: 'stderr: ${res.stderr}');
    expect(res.stdout, contains('remembered'));
    final page = landed('domain/from-file');
    expect(page.existsSync(), isTrue, reason: 'the write was a silent no-op');
    expect(page.readAsStringSync(), contains('the body from a file'));
    expect(page.readAsStringSync(), contains('the derived gist'));
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('piped stdin: the page lands on disk too', () async {
    final proc = await Process.start(
      'dart',
      args('domain/from-pipe'),
      workingDirectory: Directory.current.path,
      environment: env,
    );
    proc.stdin.add(utf8.encode('# T\n\nthe body from a pipe.\n'));
    await proc.stdin.close();
    final outText = await proc.stdout.transform(utf8.decoder).join();
    final errText = await proc.stderr.transform(utf8.decoder).join();
    final code = await proc.exitCode;

    expect(code, 0, reason: 'stderr: $errText');
    expect(outText, contains('remembered'));
    final page = landed('domain/from-pipe');
    expect(page.existsSync(), isTrue, reason: 'the write was a silent no-op');
    expect(page.readAsStringSync(), contains('the body from a pipe'));
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('an empty body fails loud — never exit 0 with nothing written', () async {
    final empty = File(p.join(sandbox.path, 'empty.md'))..writeAsStringSync('  \n\t\n');

    final res = await Process.run(
      'dart',
      [...args('domain/empty'), '-f', empty.path],
      workingDirectory: Directory.current.path,
      environment: env,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    expect(res.exitCode, isNot(0));
    expect(res.stderr, contains('no body'));
    expect(landed('domain/empty').existsSync(), isFalse);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('a failing llm fails the write loud, and lands nothing', () async {
    File(p.join(sandbox.path, 'llm'))
        .writeAsStringSync('#!/bin/sh\ncat > /dev/null\necho "boom" >&2\nexit 3\n');
    final body = File(p.join(sandbox.path, 'body.md'))..writeAsStringSync('a body');

    final res = await Process.run(
      'dart',
      [...args('domain/llm-fails'), '-f', body.path],
      workingDirectory: Directory.current.path,
      environment: env,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    expect(res.exitCode, isNot(0));
    expect(res.stderr, contains('gist derivation failed'));
    expect(landed('domain/llm-fails').existsSync(), isFalse);
  }, timeout: const Timeout(Duration(seconds: 90)));
}
