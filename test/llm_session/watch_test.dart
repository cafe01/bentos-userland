// The ref clock: what makes a face current when a body it never called commits.

import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:bentos_userland/llm_session.dart';
import 'package:chat_inference/chat_inference.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String device = '/dev/llm/fixture/echo';
const String person = 'cafe';

/// A session with nothing armed: the clock is what is under test, not the loop.
Future<Session> openSession(Directory tmp, String name) => Session.open(
      Directory(p.join(tmp.path, '$name.llm')),
      channel: const Channel(deviceId: device, config: ChatIOConfig()),
      author: person,
      runnerCommand: '',
    );

/// The clock is asynchronous: a ref reported when it is reported.
Future<void> until(
  bool Function() check, {
  required String reason,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (check()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('timed out waiting for $reason');
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('bentos-watch-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('reports the tip a transaction leaves, and only once per commit', () async {
    final session = await openSession(tmp, 'clock');
    final watch = await SessionWatch.open(session.entity);
    addTearDown(watch.close);

    final seen = <String>[];
    watch.tips.listen(seen.add);
    expect(watch.tip, await session.tip, reason: 'opening reads the current tip');

    final said = await session.say(ChatMessage.userText('oi'), author: person);
    await until(() => seen.length == 1, reason: 'the say to be reported');
    expect(watch.tip, said.id);

    final renamed = await session.rename('conversa', author: person);
    await until(() => seen.length == 2, reason: 'the rename to be reported');
    expect(watch.tip, renamed.id);

    // Long enough for the poll to have fired several times over a still ref.
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(seen, [said.id, renamed.id], reason: 'one emission per commit, never per look');
  });

  test('sees a transaction written by another body entirely', () async {
    final session = await openSession(tmp, 'stranger');
    final watch = await SessionWatch.open(session.entity);
    addTearDown(watch.close);
    final seen = <String>[];
    watch.tips.listen(seen.add);

    // Not our process and not our library: git itself, moving the ref.
    final dir = session.entity.path;
    File(p.join(dir, 'stranger.txt')).writeAsStringSync('by another hand\n');
    Process.runSync('git', ['-C', dir, 'add', 'stranger.txt']);
    Process.runSync('git', ['-C', dir, 'commit', '-q', '-m', 'say · user · stranger']);

    await until(() => seen.length == 1, reason: "the stranger's transaction");
    expect(seen.single, await session.tip);
    expect((await session.log).last.message, contains('stranger'));
  });

  test('watches one ref and is deaf to the others', () async {
    final session = await openSession(tmp, 'forked');
    final tip = (await session.tip)!;
    final fork = await session.forkAt(tip, name: 'alternative');

    final watch = await SessionWatch.open(session.entity, ref: fork.ref);
    addTearDown(watch.close);
    final seen = <String>[];
    watch.tips.listen(seen.add);

    await session.say(ChatMessage.userText('na linha principal'), author: person);
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(seen, isEmpty, reason: 'main moved; the fork did not');

    final onFork = await fork.say(ChatMessage.userText('na bifurcação'), author: person);
    await until(() => seen.length == 1, reason: 'the transaction on the fork');
    expect(watch.tip, onFork.id);
  });

  test('closes without leaking the watch', () async {
    final session = await openSession(tmp, 'closing');
    final watch = await SessionWatch.open(session.entity);
    final seen = <String>[];
    watch.tips.listen(seen.add);

    await watch.close();
    await session.say(ChatMessage.userText('depois do fim'), author: person);
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(seen, isEmpty);
  });
}
