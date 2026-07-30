// The faces' gate: the loop's own walk, driven by a person at the shell.
//
//   llm session open    channel /dev/llm/fixture/weather · system laid · get_weather declared
//   llm session monitor --arm
//   llm session watch   the answer as it forms
//   llm session say     "como está o tempo em Recife?"
//   llm session return  --call call_1
//   llm session show / log
//
// Nothing here reaches into the library to make a transaction: every write is a
// process a hand could have typed, and `llm` is on the PATH exactly as it is on
// a real machine — which is what makes the default arming, the hook, and the
// monitor's own table line real in this walk.
//
// Reading is done through the library where a poll is cheaper than a process. A
// read moves no ref, so it wakes nobody.

import 'dart:convert';
import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:bentos_userland/llm_session.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

late Directory tmp;
late Map<String, String> env;

/// The person's hand: `llm` as the shell finds it.
Future<ProcessResult> llm(List<String> args) =>
    Process.run('llm', args, environment: env, runInShell: true);

Future<void> until(
  Future<bool> Function() check, {
  Duration timeout = const Duration(seconds: 30),
  required String reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await check()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('timed out waiting for $reason');
}

/// Nothing more is coming: the log has stopped moving and no body is left to
/// wake.
Future<void> settle(Session session) async {
  var last = -1;
  var stable = 0;
  while (stable < 4) {
    final now = (await session.log).length;
    stable = now == last ? stable + 1 : 0;
    last = now;
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
}

Set<String> get liveSockets {
  final dir = Directory(p.join(Directory.systemTemp.path, 'bentos-live'));
  if (!dir.existsSync()) return const {};
  return {
    for (final entry in dir.listSync())
      if (entry.path.endsWith('.sock')) entry.path,
  };
}

void main() {
  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('bentos-llm-shell-');
    final dill = p.join(tmp.path, 'llm.dill');
    final compiled = await Process.run('dart', [
      'compile',
      'kernel',
      p.join(Directory.current.path, 'bin', 'llm.dart'),
      '-o',
      dill,
    ]);
    expect(compiled.exitCode, 0, reason: 'compiling llm: ${compiled.stderr}');

    // `llm` on the PATH — the coreutil as a machine carries it, so the armed
    // table lines the coreutil writes for itself resolve at wake time.
    final bin = Directory(p.join(tmp.path, 'bin'))..createSync();
    final shim = File(p.join(bin.path, 'llm'));
    shim.writeAsStringSync('#!/bin/sh\nexec dart $dill "\$@"\n');
    Process.runSync('chmod', ['+x', shim.path]);
    env = {
      ...Platform.environment,
      'PATH': '${bin.path}:${Platform.environment['PATH']}',
    };
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  test('a person walks the loop with nothing but the coreutil', () async {
    final dir = p.join(tmp.path, 'recife.llm');
    final functionFile = File(p.join(tmp.path, 'get_weather.json'));
    functionFile.writeAsStringSync(jsonEncode({
      'name': 'get_weather',
      'description': 'Current weather for a city.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'city': {'type': 'string'},
        },
      },
    }));

    // open — the repository, the channel, the system prompt, the arming. The
    // runner is armed by default: the person names no body.
    final opened = await llm([
      'session',
      'open',
      dir,
      '-d',
      'fixture/weather',
      '--title',
      'tempo em Recife',
      '-s',
      'Você é um meteorologista lacônico.',
      '--temperature',
      '0.7',
      '--reasoning-budget',
      '2048',
      '--function',
      functionFile.path,
      '--as',
      'cafe',
    ]);
    expect(opened.exitCode, 0, reason: opened.stderr.toString());
    expect(opened.stdout, contains('/dev/llm/fixture/weather'));
    expect(opened.stdout, contains('idle'), reason: 'only the user starts a turn');

    final session = Session(GitEntity.open(Directory(dir)));
    expect(Arming(session.entity).subscribers.single, contains('session run'));

    // The monitor arms itself — one more line in the same table, differing only
    // in what the command does.
    final armed = await llm(['session', 'monitor', dir, '--arm']);
    expect(armed.exitCode, 0, reason: armed.stderr.toString());
    expect(Arming(session.entity).subscribers.length, 2);

    // The live seam, bound before anything is said: a watch that starts after
    // the turn misses it, by design.
    final before = liveSockets;
    final watching = await Process.start(
      'llm',
      ['session', 'watch', dir, '--turns', '2', '--thinking'],
      environment: env,
      runInShell: true,
    );
    final watched = watching.stdout.transform(utf8.decoder).join();
    await until(
      () async => liveSockets.difference(before).isNotEmpty,
      reason: 'the watch to bind its socket',
    );

    // say — the origin. The face commits and stops; it never calls a device.
    final said = await llm(['session', 'say', dir, 'como está o tempo em Recife?', '--as', 'cafe']);
    expect(said.exitCode, 0, reason: said.stderr.toString());
    expect(said.stdout, startsWith('say · user · '));

    await until(
      () async => (await session.debt) is OwesResults,
      reason: 'the runner to answer with a call',
    );
    await settle(session);
    expect((await session.debt as OwesResults).callIds, ['call_1']);

    // show — the fold, as a person reads it.
    final shown = await llm(['session', 'show', dir]);
    expect(shown.exitCode, 0, reason: shown.stderr.toString());
    expect(shown.stdout, contains('tempo em Recife · /dev/llm/fixture/weather · owes-results(call_1)'));
    expect(shown.stdout, contains('~ Recife fica no litoral; vou consultar.'));
    expect(shown.stdout, contains('→ get_weather({"city":"Recife"})  call_1'));
    expect(shown.stdout, contains('stop tool_use'));
    expect(shown.stdout, contains('64 thought'));

    // return — the person occupies the executor's seat and answers by hand.
    final returned = await llm([
      'session',
      'return',
      dir,
      '--call',
      'call_1',
      '29°C, céu limpo',
      '--as',
      'cafe',
    ]);
    expect(returned.exitCode, 0, reason: returned.stderr.toString());
    expect(returned.stdout, startsWith('return · call_1 · '));

    await until(
      () async => (await session.debt) is Idle,
      reason: 'the runner to close the turn',
    );
    await settle(session);

    // The five lines, and who wrote each.
    final logged = await llm(['session', 'log', dir]);
    final lines = (logged.stdout as String).trim().split('\n');
    final line = RegExp(r'^(\w{7})\s+(\S+)\s+(\S+)');
    expect(lines.length, 5);
    expect(
      [for (final l in lines) line.firstMatch(l)!.group(3)],
      ['open', 'say', 'reply', 'return', 'reply'],
    );
    expect(
      [for (final l in lines) line.firstMatch(l)!.group(2)],
      ['cafe', 'cafe', 'model', 'cafe', 'model'],
    );
    expect(lines[1], contains('+'), reason: 'say adds one file — the diff is the payload');

    // The monitor rendered what woke it, into the wake log where a detached
    // body speaks. It was armed one transaction late, so it saw four.
    final wake = Arming(session.entity).wakeLog.readAsStringSync();
    final rendered = wake
        .trim()
        .split('\n')
        .where((line) => RegExp(r'^[0-9a-f]{7}  ').hasMatch(line))
        .toList();
    expect(rendered.length, 4, reason: 'every transaction since it was armed');
    expect(rendered.last, contains('reply · assistant · stop end_turn'));

    // The live seam carried the turns; the log carried only their settlement.
    final stream = await watched;
    await watching.exitCode;
    expect(stream, contains('Recife fica no litoral'), reason: 'the thinking, live');
    expect(stream, contains('29°C e céu limpo.'));
    expect(stream, contains('stop end_turn'));

    // And the fixture asked for no credential anywhere in this walk.
    expect((await session.state).records.length, 5);
  });

  test('a session that is not there, and a result without a call', () async {
    final missing = await llm(['session', 'show', p.join(tmp.path, 'nowhere.llm')]);
    expect(missing.exitCode, 66);
    expect(missing.stderr, contains('no entity'));

    final noCall = await llm(['session', 'return', tmp.path, 'a result']);
    expect(noCall.exitCode, 64);
    expect(noCall.stderr, contains('--call'));
  });
}
