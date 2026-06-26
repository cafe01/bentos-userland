import 'package:bentos_userland/src/mem/model/mem_node.dart';
import 'package:bentos_userland/src/mem/model/mem_resolver.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  group('acceptance: remember', () {
    test('create requires --type', () async {
      final fs = seedFs();

      final r = await runMem(
          ['-a', kAgent, '-p', kPlace, 'remember', 'new-page', '--weight', '0.7'],
          fs: fs);
      expect(r.exitCode, isNot(0));
      expect(r.err, isNot(contains('UnimplementedError')));
    });

    test('create requires --weight', () async {
      final fs = seedFs();

      final r = await runMem(
          ['-a', kAgent, '-p', kPlace, 'remember', 'new-page', '--type', 'semantic'],
          fs: fs);
      expect(r.exitCode, isNot(0));
      expect(r.err, isNot(contains('UnimplementedError')));
    });

    test('body from stdin lands in the content file', () async {
      final fs = seedFs();

      final r = await runMem([
        '-a', kAgent, '-p', kPlace,
        'remember', 'stdin-page',
        '--type', 'semantic',
        '--weight', '0.8',
      ], fs: fs, stdinContent: 'the body from stdin\n');
      expect(r.exitCode, 0);

      final node = MemResolver(agent: kAgent, fileSystem: fs).resolve(kPlace)!;
      final page = node.pagesOf(MemPageType.semantic)
          .firstWhere((pg) => pg.name == 'stdin-page');
      final content = fs.file(node.resolveTarget(page)).readAsStringSync();
      expect(content, contains('the body from stdin'));
    });

    test('body from --file lands in the content file', () async {
      final fs = seedFs();
      fs.file('/tmp/input.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('the body from file\n');

      final r = await runMem([
        '-a', kAgent, '-p', kPlace,
        'remember', 'new-page',
        '--type', 'semantic',
        '--weight', '0.8',
        '--file', '/tmp/input.md',
      ], fs: fs);
      expect(r.exitCode, 0);

      final node = MemResolver(agent: kAgent, fileSystem: fs).resolve(kPlace)!;
      final page = node.pagesOf(MemPageType.semantic)
          .firstWhere((pg) => pg.name == 'new-page');
      final content =
          fs.file(node.resolveTarget(page)).readAsStringSync();
      expect(content, contains('the body from file'));
    });

    test('--telos writes the contract into frontmatter', () async {
      final fs = seedFs();
      fs.file('/tmp/input.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('body content\n');

      await runMem([
        '-a', kAgent, '-p', kPlace,
        'remember', 'telos-page',
        '--type', 'semantic',
        '--weight', '0.8',
        '--telos', 'To prove the contract lands',
        '--file', '/tmp/input.md',
      ], fs: fs);

      final node = MemResolver(agent: kAgent, fileSystem: fs).resolve(kPlace)!;
      final page = node.pagesOf(MemPageType.semantic)
          .firstWhere((pg) => pg.name == 'telos-page');
      final raw = fs.file(node.resolveTarget(page)).readAsStringSync();
      expect(raw, contains('To prove the contract lands'));
    });

    test('--link is repeatable and replaces links list', () async {
      final fs = seedFs(
        pages: {MemPageType.semantic: {'link-page': 0.8}},
        content: {'link-page': '---\nlinks:\n  - hq/old.md\n---\nbody'},
      );

      await runMem([
        '-a', kAgent, '-p', kPlace,
        'remember', 'link-page',
        '--type', 'semantic',
        '--weight', '0.8',
        '--link', 'hq/new-a.md',
        '--link', 'hq/new-b.md',
      ], fs: fs);

      final node = MemResolver(agent: kAgent, fileSystem: fs).resolve(kPlace)!;
      final page = node.pagesOf(MemPageType.semantic)
          .firstWhere((pg) => pg.name == 'link-page');
      final raw = fs.file(node.resolveTarget(page)).readAsStringSync();
      expect(raw, contains('hq/new-a.md'));
      expect(raw, contains('hq/new-b.md'));
      expect(raw, isNot(contains('hq/old.md')));
    });

    test('--tag is repeatable and replaces tags list', () async {
      final fs = seedFs(
        pages: {MemPageType.semantic: {'tag-page': 0.8}},
        content: {'tag-page': '---\ntags:\n  - old-tag\n---\nbody'},
      );

      await runMem([
        '-a', kAgent, '-p', kPlace,
        'remember', 'tag-page',
        '--type', 'semantic',
        '--weight', '0.8',
        '--tag', 'new-tag-a',
        '--tag', 'new-tag-b',
      ], fs: fs);

      final node = MemResolver(agent: kAgent, fileSystem: fs).resolve(kPlace)!;
      final page = node.pagesOf(MemPageType.semantic)
          .firstWhere((pg) => pg.name == 'tag-page');
      final raw = fs.file(node.resolveTarget(page)).readAsStringSync();
      expect(raw, contains('new-tag-a'));
      expect(raw, isNot(contains('old-tag')));
    });

    test('reweighting an existing page updates weight without rewriting body',
        () async {
      final fs = seedFs(
        pages: {MemPageType.semantic: {'stable-page': 0.6}},
        content: {'stable-page': '---\ntelos: To keep\n---\nOriginal body.\n'},
      );

      await runMem([
        '-a', kAgent, '-p', kPlace,
        'remember', 'stable-page',
        '--type', 'semantic',
        '--weight', '0.9',
      ], fs: fs);

      final node = MemResolver(agent: kAgent, fileSystem: fs).resolve(kPlace)!;
      final page = node.pagesOf(MemPageType.semantic)
          .firstWhere((pg) => pg.name == 'stable-page');
      expect(page.weight, 0.9);
      final raw = fs.file(node.resolveTarget(page)).readAsStringSync();
      expect(raw, contains('Original body.'));
    });

    test('--telos updates without touching the body', () async {
      final fs = seedFs(
        pages: {MemPageType.semantic: {'telos-update': 0.8}},
        content: {
          'telos-update': '---\ntelos: Old telos\n---\nBody that must survive.\n',
        },
      );

      await runMem([
        '-a', kAgent, '-p', kPlace,
        'remember', 'telos-update',
        '--type', 'semantic',
        '--weight', '0.8',
        '--telos', 'New telos',
      ], fs: fs);

      final node = MemResolver(agent: kAgent, fileSystem: fs).resolve(kPlace)!;
      final page = node.pagesOf(MemPageType.semantic)
          .firstWhere((pg) => pg.name == 'telos-update');
      final raw = fs.file(node.resolveTarget(page)).readAsStringSync();
      expect(raw, contains('New telos'));
      expect(raw, contains('Body that must survive.'));
      expect(raw, isNot(contains('Old telos')));
    });
  });
}
