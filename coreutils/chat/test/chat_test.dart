import 'dart:io';

import 'package:chat/chat.dart';
import 'package:chat_inference/chat_inference.dart';
import 'package:test/test.dart';
import 'package:tx/tx.dart';

void main() {
  late Directory tmp;
  late TxRepo repo;
  late ChatSession session;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('chat_test_');
    File('${tmp.path}/place.yaml').writeAsStringSync('place: test\n');
    repo = TxRepo(Directory('${tmp.path}/.tx/john'), 'john');
    session = ChatSession(repo);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<int> commitCount() async {
    final r = await Process.run(
      'git',
      ['-C', repo.dir.path, 'rev-list', '--count', 'HEAD'],
    );
    return int.parse((r.stdout as String).trim());
  }

  group('ChatSession — the chat↔tx seam', () {
    test('ensureOpen creates a session on first turn; history starts empty', () async {
      await session.ensureOpen();
      expect(repo.hasSession, isTrue);
      expect(session.history(), isEmpty);
    });

    test('a recorded message round-trips through the framing', () async {
      await session.ensureOpen();
      await session.record(ChatMessage.userText('hello'));

      final history = session.history();
      expect(history, hasLength(1));
      expect(history.single.role, equals(ChatRole.user));
      expect(
        history.single.content.whereType<TextContent>().single.text,
        equals('hello'),
      );
    });

    test('a full turn (user, assistant+funccall, tool-result) round-trips', () async {
      await session.ensureOpen();
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

    test('one record == one commit (per-mutation write-ahead)', () async {
      await session.ensureOpen(); // base commit
      await session.record(ChatMessage.userText('a'));
      await session.record(ChatMessage(role: ChatRole.assistant, content: [
        TextContent('b'),
      ]));
      // base (1) + 2 records = 3 commits.
      expect(await commitCount(), equals(3));
    });

    test('continuity lives on disk, not memory: a fresh session reads it back',
        () async {
      await session.ensureOpen();
      await session.record(ChatMessage.userText('remember electric blue'));
      await session.record(ChatMessage(role: ChatRole.assistant, content: [
        TextContent('noted'),
      ]));

      // A brand-new ChatSession over the SAME repo dir — no shared memory.
      final reopened = ChatSession(TxRepo(repo.dir, 'john'));
      final h = reopened.history();
      expect(h, hasLength(2));
      expect(h.first.content.whereType<TextContent>().single.text,
          equals('remember electric blue'));
    });

    test('multi-line text does not break the JSONL framing', () async {
      await session.ensureOpen();
      await session.record(ChatMessage.userText('line one\nline two\nline three'));

      final h = session.history();
      expect(h, hasLength(1)); // still ONE record despite embedded newlines
      expect(
        h.single.content.whereType<TextContent>().single.text,
        equals('line one\nline two\nline three'),
      );
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
