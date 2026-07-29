// The construction gate: the loop's own fixture, walked on the real floor.
//
//   open       channel /dev/llm/fixture/weather · system laid · get_weather declared
//   say        user: "como está o tempo em Recife?"
//   reply      assistant: thinking · call get_weather(city=Recife) · stop tool_use
//   return     executor: get_weather#1 → 29°C, céu limpo
//   reply      assistant: "29°C e céu limpo." · stop end_turn
//
// Real means real: the entity is a git repository, the wake is git's own hook
// firing a process that folds and exits, and the device is `/dev/llm/*` reached
// through the portal. Nothing in the loop is emulated except the model's mind.

import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:bentos_userland/llm_session.dart';
import 'package:chat_inference/chat_inference.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String device = '/dev/llm/fixture/weather';
const String person = 'cafe';

final FunctionDefinition getWeather = FunctionDefinition(
  name: 'get_weather',
  description: 'Current weather for a city.',
  inputSchema: const {
    'type': 'object',
    'properties': {
      'city': {'type': 'string'},
    },
  },
);

Channel channel({double temperature = 0.7}) => Channel(
      deviceId: device,
      config: ChatIOConfig(
        temperature: temperature,
        maxTokens: 1024,
        reasoningBudget: 2048,
        functions: [getWeather],
        functionChoice: const AutoChoice(),
      ),
    );

late Directory tmp;
late String fixtureLlm;

/// The real floor is asynchronous: a woken body lands when it lands.
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
/// wake. Every chain of consequence ends at idle, so this always terminates.
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

void main() {
  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('bentos-llm-gate-');
    // The body the hook wakes, compiled once: `llm` with the fixture vendor in
    // its boot table.
    fixtureLlm = p.join(tmp.path, 'fixture_llm.dill');
    final compiled = await Process.run('dart', [
      'compile',
      'kernel',
      p.join(Directory.current.path, 'test', 'llm_session', 'fixture_llm.dart'),
      '-o',
      fixtureLlm,
    ]);
    expect(compiled.exitCode, 0, reason: 'compiling the runner: ${compiled.stderr}');
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  test('the loop walks its fixture on the real floor and lands at idle', () async {
    final dir = Directory(p.join(tmp.path, 'recife.llm'));
    final witness = p.join(tmp.path, 'monitor.log');

    // The wiring: one hook consulting one table — the runner armed with a wake,
    // the monitor armed signal-only. They differ in what the command does.
    final session = await Session.open(
      dir,
      channel: channel(),
      author: person,
      title: 'tempo em Recife',
      systemPrompt: 'Você é um meteorologista lacônico.',
      runnerCommand:
          'dart $fixtureLlm session run "\$BENTOS_ENTITY" --ref "\$BENTOS_REF"',
    );
    Arming(session.entity)
        .subscribe('echo "\$BENTOS_REF \$BENTOS_NEW" >> $witness');

    // The live seam, opened before anything is said: the runner will publish
    // into it, and it is persisted nowhere.
    final watch = await LiveWatch.bind(session.entity);
    final streamed = <ChatEvent>[];
    watch.events.listen(streamed.add);

    // open — nothing is owed: only the user initiates.
    expect(await session.debt, isA<Idle>());
    await settle(session);
    expect((await session.log).length, 1, reason: 'woken by open, the runner stood down');

    // say — the origin. The face commits and stops; it never calls a device.
    await session.say(
      ChatMessage.userText('como está o tempo em Recife?'),
      author: person,
    );
    expect(await session.debt, isA<OwesInference>());
    await until(
      () async => (await session.debt) is OwesResults,
      reason: 'the runner to answer with a call',
    );
    await settle(session);

    expect((await session.debt as OwesResults).callIds, ['call_1']);
    final calling = (await session.state).records.last;
    expect(calling.message.role, ChatRole.assistant);
    expect(calling.message.content.whereType<ThinkingContent>().single.text,
        'Recife fica no litoral; vou consultar.');
    expect(calling.calls.single.arguments, {'city': 'Recife'});
    expect(calling.meta!.stopReason, const FunctionCall());
    expect(calling.meta!.usage!.reasoningTokens, 64);
    expect(calling.marker!.deviceId, device);
    expect(calling.marker!.config.temperature, 0.7);
    expect(calling.marker!.config.functions!.single.name, 'get_weather');

    // return — the person occupies the executor's seat and answers by hand.
    await session.returnResult(
      callId: 'call_1',
      content: [const TextContent('29°C, céu limpo')],
      author: person,
    );
    expect(await session.debt, isA<OwesInference>());
    await until(
      () async => (await session.debt) is Idle,
      reason: 'the runner to close the turn',
    );
    await settle(session);

    // The five lines, and everything that happened is there.
    final log = await session.log;
    expect(log.map((t) => t.kind).toList(), ['open', 'say', 'reply', 'return', 'reply']);
    expect(log.map((t) => t.author).toList(), [person, person, 'model', person, 'model']);
    expect(log.last.message, contains('stop end_turn'));

    // The machine is folded at every point, never stored.
    final folded = <String>[];
    for (final tx in log) {
      folded.add(SessionState.fold(await session.entity.tree(tx.id)).debt.toString());
    }
    expect(folded,
        ['idle', 'owes-inference', 'owes-results(call_1)', 'owes-inference', 'idle']);

    // The runner woke on all five transactions and worked on two: the ones it
    // stood down on include its own commits, and the fold is what makes that
    // safe. The monitor, armed one transaction later, saw the four that
    // followed it — arming is per-subscriber and takes effect where it lands.
    expect(File(witness).readAsLinesSync().length, 4,
        reason: 'the monitor was signalled by every transaction since it was armed');

    // The stream carried the live turn; the log carried the settled one.
    expect(streamed.whereType<TextDelta>().map((e) => e.text).join(),
        '29°C e céu limpo.');
    expect(streamed.whereType<Complete>().length, 2);
    final state = await session.state;
    expect(state.records.last.message.content.whereType<TextContent>().single.text,
        '29°C e céu limpo.');
    expect(state.systemPrompt, 'Você é um meteorologista lacônico.');
    await watch.close();

    // A transaction's diff is its payload: one file per message.
    final sayDiff = await session.entity.diff(log[1].id);
    expect(sayDiff.added.single, startsWith('$messagesDir/'));
    expect(sayDiff.changed, isEmpty);

    // And the session is legible on disk without any of our code.
    expect(File(p.join(dir.path, channelFile)).existsSync(), isTrue);
    expect(
      Directory(p.join(dir.path, messagesDir)).listSync().length,
      5,
      reason: 'system, user, the call, the result, the answer — one file each',
    );
    final show = Process.runSync('git', ['-C', dir.path, 'log', '--oneline']);
    expect(show.stdout.toString().trim().split('\n').length, 5);
  });
}
