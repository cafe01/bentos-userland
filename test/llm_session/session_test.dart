// The session's own semantics, on the real floor but without the hook: the
// runner is woken by hand so the walk stays in one process and the assertions
// can sit between the turns.
//
// What is real here is everything the gate makes real except the wake — the
// repository, the compare-and-swap, the device behind `/dev/llm/*`.

import 'dart:io';

import 'package:bentos_userland/boot.dart';
import 'package:bentos_userland/llm.dart';
import 'package:bentos_userland/llm_session.dart';
import 'package:chat_inference/chat_inference.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

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

Channel channel(String model, {double temperature = 0.7}) => Channel(
      deviceId: '/dev/llm/fixture/$model',
      config: ChatIOConfig(
        temperature: temperature,
        maxTokens: 1024,
        functions: [getWeather],
        functionChoice: const AutoChoice(),
      ),
    );

late Directory tmp;
var _seq = 0;

/// A session nobody is armed on: the wake is this file's business.
Future<Session> openSession(String model, {String? systemPrompt}) => Session.open(
      Directory(p.join(tmp.path, 's${_seq++}.llm')),
      channel: channel(model),
      author: person,
      systemPrompt: systemPrompt,
      runnerCommand: '',
    );

void main() {
  setUpAll(() {
    registerLlmDriver(
      fixtureVendor,
      (model, ch) => fixtureChatDriver(model: model).serveChannel(ch),
    );
  });

  setUp(() => tmp = Directory.systemTemp.createTempSync('bentos-llm-session-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('a transaction diff is its payload — one file per message', () async {
    final session = await openSession('text', systemPrompt: 'sê breve');
    final opened = (await session.log).single;
    final said = await session.say(ChatMessage.userText('oi'), author: person);

    final openDiff = await session.entity.diff(opened.id);
    expect(openDiff.added, contains(channelFile));
    expect(openDiff.added, contains(titleFile));
    expect(openDiff.added.where((f) => f.startsWith('$messagesDir/')).length, 1);

    final sayDiff = await session.entity.diff(said.id);
    expect(sayDiff.added.length, 1);
    expect(sayDiff.added.single, startsWith('$messagesDir/'));
    expect(sayDiff.changed, isEmpty);
    expect(sayDiff.removed, isEmpty);
  });

  test('the record round-trips through its file', () async {
    final session = await openSession('text', systemPrompt: 'sê breve');
    final message = ChatMessage(role: ChatRole.user, content: const [
      TextContent('olha isto'),
      BinaryContent(mimeType: 'image/png', uri: 'file:///tmp/a.png'),
    ]);
    await session.say(message, author: person);
    expect((await session.state).records.last.message, message);

    const meta = ChatMetadata(
      model: 'fixture/text',
      stopReason: MaxTokens(),
      usage: TokenUsage(inputTokens: 1, outputTokens: 2, cacheReadTokens: 3),
    );
    await session.reply(
      ChatMessage.assistantText('truncad'),
      meta: meta,
      marker: TurnMarker(
        deviceId: '/dev/llm/fixture/text',
        config: channel('text', temperature: 0.2).config,
      ),
      author: 'model',
    );
    final assistant = (await session.state).records.last;
    expect(assistant.meta!.stopReason, const MaxTokens());
    expect(assistant.meta!.usage!.cacheReadTokens, 3);
    expect(assistant.marker!.config.temperature, 0.2);
    expect(assistant.marker!.config.functions!.single.name, 'get_weather');
  });

  test('the marker freezes what a turn ran under; configure moves only the channel',
      () async {
    final session = await openSession('text', systemPrompt: 'x');
    final runner = SessionRunner(session: session);

    await session.say(ChatMessage.userText('um'), author: person);
    expect(await runner.wake(), isTrue);
    await session.configure(
      channel('text', temperature: 0.1),
      author: person,
      note: 'temperature 0.1',
    );
    await session.say(ChatMessage.userText('dois'), author: person);
    expect(await runner.wake(), isTrue);

    final markers = [
      for (final r in (await session.state).records)
        if (r.marker != null) r.marker!.config.temperature,
    ];
    expect(markers, [0.7, 0.1], reason: 'a past turn is a fact; the channel is intent');
    expect((await session.log).map((t) => t.kind).toList(),
        ['open', 'say', 'reply', 'configure', 'say', 'reply']);
    expect(await session.debt, isA<Idle>());
  });

  test('two calls, two returns — the debt is coverage and the results are one message',
      () async {
    final session = await openSession('two-cities', systemPrompt: 'x');
    final runner = SessionRunner(session: session);

    await session.say(ChatMessage.userText('Recife e Olinda?'), author: person);
    expect(await runner.wake(), isTrue);
    expect((await session.debt as OwesResults).callIds, ['a', 'b']);

    final first = await session.returnResult(
      callId: 'a',
      content: [const TextContent('29°C')],
      author: person,
    );
    expect((await session.debt as OwesResults).callIds, ['b'],
        reason: "still the executor's debt — the runner must not fire");
    expect(await runner.wake(), isFalse,
        reason: 'woken by the return, it folds and stands down');

    final second = await session.returnResult(
      callId: 'b',
      content: [const TextContent('30°C')],
      author: person,
    );
    expect(await session.debt, isA<OwesInference>());

    // One ontology message, extended: the first return created the file, the
    // second changed it.
    expect((await session.entity.diff(first.id)).added.length, 1);
    expect((await session.entity.diff(second.id)).changed.length, 1);
    expect((await session.entity.diff(second.id)).added, isEmpty);

    expect(await runner.wake(), isTrue);
    final executor = (await session.state).records.singleWhere((r) => r.isExecutorTurn);
    expect(executor.results.map((r) => r.callId).toList(), ['a', 'b']);
    expect(await session.debt, isA<Idle>());
  });

  test('two bodies raised for one occurrence: one reply survives', () async {
    final session = await openSession('text', systemPrompt: 'x');
    await session.say(ChatMessage.userText('oi'), author: person);

    // Both fold the same tip, both pay for a model call, and the ref update is
    // a compare-and-swap.
    final outcomes = await Future.wait([
      SessionRunner(session: session).wake(),
      SessionRunner(session: session).wake(),
    ]);

    expect(outcomes.where((worked) => worked).length, 1,
        reason: 'the loser re-folds and discards the turn it bought');
    expect((await session.log).where((t) => t.kind == 'reply').length, 1);
    expect(await session.debt, isA<Idle>());
  });

  test('revise: amending the system message keeps the conversation, rewriting a turn re-runs it',
      () async {
    final session = await openSession('text', systemPrompt: 'sê breve');
    final runner = SessionRunner(session: session);
    await session.say(ChatMessage.userText('primeira'), author: person);
    await runner.wake();

    final records = (await session.state).records;
    final systemId = records.first.id;
    final userId = records[1].id;
    expect(records.length, 3);

    // The system prompt is data: amended for subsequent turns, and the
    // conversation stands.
    await session.revise(systemId, ChatMessage.systemText('sê prolixo'), author: person);
    expect((await session.state).systemPrompt, 'sê prolixo');
    expect((await session.state).records.length, 3);
    expect(await session.debt, isA<Idle>());
    expect(await runner.wake(), isFalse, reason: 'amending data owes no inference');

    // Rewriting a turn to run again from there discards what followed it.
    await session.revise(
      userId,
      ChatMessage.userText('segunda'),
      author: person,
      discardTail: true,
    );
    expect((await session.state).records.length, 2);
    expect(await session.debt, isA<OwesInference>());
    expect(await runner.wake(), isTrue);
    expect((await session.state).records.length, 3);

    // Nothing was lost: the discarded turn is in the log.
    final history = await session.log;
    expect(history.map((t) => t.kind).toList(),
        ['open', 'say', 'reply', 'revise', 'revise', 'reply']);
    final discarded = await session.entity.tree(history[2].id);
    expect(discarded.keys.where((f) => f.startsWith('$messagesDir/')).length, 3);
  });

  test('fork: a branch at any turn, the parent intact', () async {
    final session = await openSession('text', systemPrompt: 'x');
    await session.say(ChatMessage.userText('oi'), author: person);
    await SessionRunner(session: session).wake();
    final atReply = (await session.tip)!;
    final parentLog = (await session.log).length;

    final fork = await session.forkAt(atReply, name: 'fork-a');
    await fork.configure(
      channel('text', temperature: 0.0),
      author: person,
      note: 'temperature 0.0',
    );
    await fork.say(ChatMessage.userText('e agora, mais frio?'), author: person);

    // The fork is no transaction of the parent at all.
    expect((await session.log).length, parentLog);
    expect(await session.tip, atReply);
    expect(await session.debt, isA<Idle>());

    // Parentage is the shared history, never an invented field.
    final forkLog = await fork.log;
    expect(forkLog.length, parentLog + 2);
    expect(forkLog.take(parentLog).map((t) => t.id).toList(),
        (await session.log).map((t) => t.id).toList());
    expect(await fork.debt, isA<OwesInference>());
    expect((await fork.state).channel.config.temperature, 0.0);

    // Both continuations stand, and the runner answers whichever it is woken on.
    expect(await SessionRunner(session: fork).wake(), isTrue);
    expect(await fork.debt, isA<Idle>());
    expect((await session.log).length, parentLog);
  });
}
