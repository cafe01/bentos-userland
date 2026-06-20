import 'dart:io';

import 'package:chat/chat.dart';
import 'package:chat_inference/chat_inference.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('chat_test_');
    File('${tmp.path}/place.yaml').writeAsStringSync('place: test\n');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  // The session worktree on the tx model: <place>/.tx/<entity>/<scope>/<thread>/.
  File logFile(String entity, {String scope = 'main', String thread = 'main'}) =>
      File('${tmp.path}/.tx/$entity/$scope/$thread/session.jsonl');

  Future<int> commitCount(String entity,
      {String scope = 'main', String thread = 'main'}) async {
    final worktree = '${tmp.path}/.tx/$entity/$scope/$thread';
    final r = await Process.run(
      'git',
      ['-C', worktree, 'rev-list', '--count', 'HEAD'],
    );
    return int.parse((r.stdout as String).trim());
  }

  group('ChatSession — the chat↔tx seam on the worktree model', () {
    test('open creates a session; a system-less history starts empty', () async {
      final session = await ChatSession.open('john', tmp);
      expect(session.history(), isEmpty);
    });

    test('a recorded message round-trips through the framing', () async {
      final session = await ChatSession.open('john', tmp);
      await session.record(ChatMessage.userText('hello'));

      final history = session.history();
      expect(history, hasLength(1));
      expect(history.single.role, equals(ChatRole.user));
      expect(
        history.single.content.whereType<TextContent>().single.text,
        equals('hello'),
      );
    });

    test('a full turn (user, assistant+funccall, tool-result) round-trips',
        () async {
      final session = await ChatSession.open('john', tmp);
      await session.record(ChatMessage.userText('search dart'));
      await session.record(ChatMessage(role: ChatRole.assistant, content: [
        TextContent('let me look'),
        FunctionCallContent(
          id: 'c1',
          name: 'websearch',
          arguments: const {'query': 'dart'},
        ),
      ]));
      await session.record(ChatMessage(role: ChatRole.user, content: [
        FunctionResultContent(
          callId: 'c1',
          content: [TextContent('result text')],
        ),
      ]));

      final h = session.history();
      expect(h, hasLength(3));
      expect(h[1].content.whereType<FunctionCallContent>().single.name,
          equals('websearch'));
      expect(h[2].content.whereType<FunctionResultContent>().single.callId,
          equals('c1'));
    });

    test('one commitTurn == one commit on top of the base (turns = commits)',
        () async {
      final session = await ChatSession.open('john', tmp);
      final base = await commitCount('john'); // scope-new base commit
      await session.record(ChatMessage.userText('a'));
      await session.record(ChatMessage(role: ChatRole.assistant, content: [
        TextContent('b'),
      ]));
      await session.commitTurn();
      // The whole turn's batch of records seals as ONE commit.
      expect(await commitCount('john'), equals(base + 1));
    });

    test('continuity lives on disk, not memory: a fresh open reads it back',
        () async {
      final session = await ChatSession.open('john', tmp);
      await session.record(ChatMessage.userText('remember electric blue'));
      await session.record(ChatMessage(role: ChatRole.assistant, content: [
        TextContent('noted'),
      ]));

      // A brand-new ChatSession over the SAME place — no shared memory.
      final reopened = await ChatSession.open('john', tmp);
      final h = reopened.history();
      expect(h, hasLength(2));
      expect(h.first.content.whereType<TextContent>().single.text,
          equals('remember electric blue'));
    });

    test('multi-line text does not break the JSONL framing', () async {
      final session = await ChatSession.open('john', tmp);
      await session.record(ChatMessage.userText('line one\nline two\nline three'));

      final h = session.history();
      expect(h, hasLength(1)); // still ONE record despite embedded newlines
      expect(
        h.single.content.whereType<TextContent>().single.text,
        equals('line one\nline two\nline three'),
      );
    });

    test('reopening an existing session does NOT re-record the system message',
        () async {
      const sys = 'You are a helpful assistant named Iris.';
      await ChatSession.open('john', tmp,
          systemMessages: [ChatMessage.systemText(sys)]);
      // Second open over the SAME place: the scope already exists, so the
      // establishment-time system write must NOT fire again.
      final reopened = await ChatSession.open('john', tmp,
          systemMessages: [ChatMessage.systemText(sys)]);
      expect(reopened.history(), hasLength(1));
    });

    // --- #20 regression: a native turn carries its system message ----------
    //
    // The trap (golden-rule-applies-to-assertions): a non-empty / "some
    // system message exists" assert passes by accident. We assert the EXACT
    // system text — both decoded from history and present in the raw log on
    // disk — so a wrong serialization actually fails.
    group('#20 — system message recorded at establishment', () {
      const sys = 'You are Iris. Be terse. Marker: electric-blue-7741.';

      test('history carries the system message with its EXACT text', () async {
        final session = await ChatSession.open('john', tmp,
            systemMessages: [ChatMessage.systemText(sys)]);

        final h = session.history();
        expect(h, hasLength(1));
        expect(h.single.role, equals(ChatRole.system));
        expect(
          h.single.content.whereType<TextContent>().single.text,
          equals(sys),
        );
      });

      test('the EXACT system text lands in session.jsonl on disk', () async {
        await ChatSession.open('john', tmp,
            systemMessages: [ChatMessage.systemText(sys)]);

        final raw = logFile('john').readAsStringSync();
        expect(raw, contains(sys));
      });

      test('it survives a fresh open — continuity on disk, not memory',
          () async {
        await ChatSession.open('john', tmp,
            systemMessages: [ChatMessage.systemText(sys)]);

        final reopened = await ChatSession.open('john', tmp);
        final h = reopened.history();
        expect(h, hasLength(1));
        expect(
          h.single.content.whereType<TextContent>().single.text,
          equals(sys),
        );
      });
    });
  });

  group('tools', () {
    test('builtinTools ships websearch', () {
      expect(builtinTools().map((t) => t.name), contains('websearch'));
    });

    test('loadTools reads *.json definitions from a dir', () {
      final dir = Directory('${tmp.path}/tools')..createSync();
      File('${dir.path}/echo.json').writeAsStringSync(
        '{"name":"echo","description":"echoes","inputSchema":{"type":"object"}}',
      );
      final loaded = loadTools(dir.path);
      expect(loaded, hasLength(1));
      expect(loaded.single.name, equals('echo'));
    });

    test('loadTools on a missing dir is empty', () {
      expect(loadTools('${tmp.path}/nope'), isEmpty);
    });
  });
}
