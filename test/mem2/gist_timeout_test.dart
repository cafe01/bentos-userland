/// Process-boundary test: `llmGist` must bound the live model call. The seam
/// spawns `llm` over the network with nothing else limiting it, so a stalled
/// request used to hang `mem remember` forever — the write's whole latency is
/// this call. Proving it needs a real child that never answers, so the test
/// runs the seam in a subprocess whose PATH resolves `llm` to a fake that
/// sleeps.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('a stalled llm fails the write instead of hanging it', () async {
    final packageRoot = Directory.current.path;
    final sandbox = Directory.systemTemp.createTempSync('gist-timeout-');
    addTearDown(() => sandbox.deleteSync(recursive: true));

    final fakeLlm = File(p.join(sandbox.path, 'llm'));
    fakeLlm.writeAsStringSync('#!/bin/sh\nsleep 300\n');
    Process.runSync('chmod', ['+x', fakeLlm.path]);

    // The driver lives inside the package so `package:bentos_userland` resolves.
    final driverDir = Directory(p.join(packageRoot, '.dart_tool', 'gist_timeout_test'))
      ..createSync(recursive: true);
    addTearDown(() => driverDir.deleteSync(recursive: true));
    final driver = File(p.join(driverDir.path, 'drive_gist.dart'));
    driver.writeAsStringSync('''
import 'package:bentos_userland/src/mem2/gist_deriver.dart';

Future<void> main() async {
  try {
    await llmGist('a body', timeout: const Duration(seconds: 2));
    print('NO-TIMEOUT');
  } on GistDerivationFailed catch (e) {
    print(e);
  }
}
''');

    final started = DateTime.now();
    final result = await Process.run(
      'dart',
      ['run', driver.path],
      workingDirectory: packageRoot,
      environment: {'PATH': '${sandbox.path}:${Platform.environment['PATH']}'},
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    final elapsed = DateTime.now().difference(started);

    expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
    expect(result.stdout, contains('did not answer within 2s'));
    expect(result.stdout, contains('--gist'));
    expect(elapsed.inSeconds, lessThan(60), reason: 'the seam hung: $elapsed');
  }, timeout: const Timeout(Duration(seconds: 120)));
}
