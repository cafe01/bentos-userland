import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:websearch/websearch.dart';

/// Creates a fake `ddgr` script in [dir] that emits [json] to stdout.
void _writeFakeDdgr(Directory dir, String json, {int exitCode = 0}) {
  final script = File('${dir.path}/ddgr');
  script.writeAsStringSync(
    '#!/bin/sh\necho \'$json\'\nexit $exitCode\n',
  );
  script.setLastModifiedSync(DateTime.now());
  Process.runSync('chmod', ['+x', script.path]);
}

void main() {
  group('SearchResult', () {
    test('fromDdgr maps abstract → snippet', () {
      final r = SearchResult.fromDdgr({
        'title': 'Dart SDK',
        'url': 'https://dart.dev',
        'abstract': 'The Dart language home.',
      });
      expect(r.title, 'Dart SDK');
      expect(r.url, 'https://dart.dev');
      expect(r.snippet, 'The Dart language home.');
    });

    test('toJsonl emits exactly {title,url,snippet}', () {
      final r = SearchResult(
        title: 'Dart SDK',
        url: 'https://dart.dev',
        snippet: 'The Dart language home.',
      );
      final decoded = jsonDecode(r.toJsonl()) as Map<String, dynamic>;
      expect(decoded.keys.toSet(), {'title', 'url', 'snippet'});
      expect(decoded['title'], 'Dart SDK');
      expect(decoded['url'], 'https://dart.dev');
      expect(decoded['snippet'], 'The Dart language home.');
    });

    test('toJsonl is a single line (no newlines in value)', () {
      final r = SearchResult(
        title: 'T',
        url: 'https://example.com',
        snippet: 'S',
      );
      expect(r.toJsonl(), isNot(contains('\n')));
    });
  });

  group('Engine', () {
    test('parse ddgr', () => expect(Engine.parse('ddgr'), Engine.ddgr));
    test('parse googler', () => expect(Engine.parse('googler'), Engine.googler));
    test('parse unknown throws', () {
      expect(() => Engine.parse('bing'), throwsArgumentError);
    });
  });

  group('search() — ddgr stubbed via PATH', () {
    late Directory fakeDir;

    setUp(() {
      fakeDir = Directory.systemTemp.createTempSync('fake_ddgr_');
    });

    tearDown(() => fakeDir.deleteSync(recursive: true));

    test('single result round-trips correctly', () async {
      const payload = r'''
[{"title":"Dart SDK","url":"https://dart.dev","abstract":"The Dart home."}]
''';
      _writeFakeDdgr(fakeDir, payload.trim());

      final results = await searchWithPath(
        'dart',
        engine: Engine.ddgr,
        count: 1,
        pathOverride: fakeDir.path,
      );

      expect(results, hasLength(1));
      expect(results[0].title, 'Dart SDK');
      expect(results[0].url, 'https://dart.dev');
      expect(results[0].snippet, 'The Dart home.');
    });

    test('multiple results all returned', () async {
      final items = List.generate(
        3,
        (i) =>
            '{"title":"T$i","url":"https://example.com/$i","abstract":"S$i"}',
      ).join(',');
      _writeFakeDdgr(fakeDir, '[$items]');

      final results = await searchWithPath(
        'query',
        engine: Engine.ddgr,
        pathOverride: fakeDir.path,
      );
      expect(results, hasLength(3));
      expect(results[1].snippet, 'S1');
    });

    test('engine not found → WebsearchEngineNotFoundError', () async {
      // empty dir — no ddgr binary
      final emptyDir = Directory.systemTemp.createTempSync('no_ddgr_');
      addTearDown(() => emptyDir.deleteSync(recursive: true));

      expect(
        () => searchWithPath('x', pathOverride: emptyDir.path),
        throwsA(isA<WebsearchEngineNotFoundError>()),
      );
    });

    test('engine exits non-zero → WebsearchQueryError', () async {
      _writeFakeDdgr(fakeDir, '', exitCode: 1);

      expect(
        () => searchWithPath('x', pathOverride: fakeDir.path),
        throwsA(isA<WebsearchQueryError>()),
      );
    });

    test('engine returns empty array → WebsearchQueryError', () async {
      _writeFakeDdgr(fakeDir, '[]');

      expect(
        () => searchWithPath('x', pathOverride: fakeDir.path),
        throwsA(isA<WebsearchQueryError>()),
      );
    });

    test('engine returns non-JSON → WebsearchQueryError', () async {
      _writeFakeDdgr(fakeDir, 'not json at all');

      expect(
        () => searchWithPath('x', pathOverride: fakeDir.path),
        throwsA(isA<WebsearchQueryError>()),
      );
    });

    test('googler → UnimplementedError', () {
      expect(
        () => searchWithPath('x', engine: Engine.googler, pathOverride: fakeDir.path),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });
}
