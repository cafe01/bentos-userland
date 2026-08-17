import 'dart:async';
import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:bentos_userland/src/mem/attention.dart';
import 'package:bentos_userland/src/mem/page.dart';
import 'package:bentos_userland/src/mem/surface.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../entity/helpers.dart';

/// `--help` answers through `print`, not through the sink [Mem.call] hands
/// the runner — the args package's own `Command.printUsage` calls the global
/// function directly. Captured the same way a real terminal would see it,
/// the same technique `entity`'s own grammar test uses.
Future<String> printedBy(Future<void> Function() body) async {
  final buffer = StringBuffer();
  await runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => buffer.writeln(line),
    ),
  );
  return buffer.toString();
}

final class _Out implements Sink<String> {
  final buffer = StringBuffer();
  @override
  void add(String data) => buffer.write(data);
  @override
  void close() {}
  String get text => buffer.toString();
}

void main() {
  late Site site;

  setUp(() => site = Site());
  tearDown(() => site.dispose());

  Directory materialize(String name) {
    final entity = Entity(name, from: site.root.path).create(actor: testActor);
    entity.instance('main').create();
    final where = Directory(p.join(site.root.path, entity.name));
    entity.instance('main').materialize(at: where.path);
    return where;
  }

  Mem mem() => Mem(
        vantage: site.root.path,
        out: _Out(),
        diagnostics: _Out(),
        environment: const {},
      );

  const signed = ['--actor', 'Tester <tester@test.local>'];

  group('invocation — the grammar `--help` prints, one declaration per verb',
      () {
    // Every verb, and the exact positional grammar it must teach — a bare
    // `[arguments]` is the args package's own default when nobody declared
    // one, and every verb here must have overridden it, including the ones
    // that take none at all (`survey`).
    const grammar = {
      'survey': 'survey',
      'recall': 'recall [<topic>...]',
      'walk': 'walk <entry>...',
      'health': 'health [<topic>]',
      'remember': 'remember <topic>',
      'refocus': 'refocus [<topic>]',
      'tag': 'tag [<topic>]',
      'gist': 'gist [<topic>]',
      'forget': 'forget <topic>',
    };

    for (final entry in grammar.entries) {
      test('`mem ${entry.key}` prints its own positionals, not a generic '
          '[arguments]', () async {
        final printed = await printedBy(() => mem().call([entry.key, '--help']));
        expect(printed, contains('Usage: mem ${entry.value}'));
        expect(printed, isNot(contains('[arguments]')),
            reason: 'the default the args package prints when nobody '
                'declared a grammar — every verb here must have overridden it');
      });
    }
  });

  group('the optional tier — health, refocus, tag, gist', () {
    test('tag with no topic falls back to selector-only reach', () async {
      materialize('alfred.mem');
      File(p.join(site.root.path, 'alfred.mem', 'a.md')).writeAsStringSync(
        Page(
          topic: 'a',
          fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
          body: 'body of a',
        ).serialize(),
      );
      final cli = mem();
      final code =
          await cli.call(['tag', '-b', 'alfred.mem', ...signed, '--add', 'x', '--cool']);
      expect(code, 0);
    });

    test('tag with a topic reaches exactly that page', () async {
      materialize('alfred.mem');
      File(p.join(site.root.path, 'alfred.mem', 'a.md')).writeAsStringSync(
        Page(
          topic: 'a',
          fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
          body: 'body of a',
        ).serialize(),
      );
      final cli = mem();
      final code = await cli.call(['tag', 'a', '-b', 'alfred.mem', ...signed, '--add', 'x']);
      expect(code, 0);
    });

    test('a second, uncounted word is refused rather than silently dropped '
        '— the bug this closes', () async {
      materialize('alfred.mem');
      File(p.join(site.root.path, 'alfred.mem', 'alice.md')).writeAsStringSync(
        Page(
          topic: 'alice',
          fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
          body: 'body of alice',
        ).serialize(),
      );
      final out = _Out();
      final diag = _Out();
      final cli = Mem(
        vantage: site.root.path,
        out: out,
        diagnostics: diag,
        environment: const {},
      );
      // The exact shape found in use: `mem tag --add foo alice bob` used to
      // tag `alice` and let `bob` vanish at exit 0.
      final code = await cli
          .call(['tag', 'alice', 'bob', '-b', 'alfred.mem', ...signed, '--add', 'foo']);
      expect(code, 2);
      expect(diag.text, contains('unexpected argument(s): bob'));
    });
  });

  group('recall — variadic, zero allowed', () {
    Directory seed(String bank, List<String> topics) {
      final root = materialize(bank);
      for (final topic in topics) {
        File(p.join(root.path, '$topic.md')).writeAsStringSync(Page(
          topic: topic,
          fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
          body: 'body of $topic',
        ).serialize());
      }
      return root;
    }

    test('zero topics falls back to selector-only reach', () async {
      seed('alfred.mem', ['a', 'b']);
      final out = _Out();
      final diag = _Out();
      final cli = Mem(
        vantage: site.root.path,
        out: out,
        diagnostics: diag,
        environment: const {},
      );
      final code = await cli.call(['recall', '-b', 'alfred.mem']);
      expect(code, 0);
      expect(out.text, contains('body of a'));
      expect(out.text, contains('body of b'));
    });

    test('one topic reaches exactly that page', () async {
      seed('alfred.mem', ['a', 'b']);
      final out = _Out();
      final diag = _Out();
      final cli = Mem(
        vantage: site.root.path,
        out: out,
        diagnostics: diag,
        environment: const {},
      );
      final code = await cli.call(['recall', 'a', '-b', 'alfred.mem']);
      expect(code, 0);
      expect(out.text, contains('body of a'));
      expect(out.text, isNot(contains('body of b')));
    });

    test('many topics reach every page named, no upper bound', () async {
      seed('alfred.mem', ['a', 'b', 'c']);
      final out = _Out();
      final diag = _Out();
      final cli = Mem(
        vantage: site.root.path,
        out: out,
        diagnostics: diag,
        environment: const {},
      );
      final code = await cli.call(['recall', 'a', 'b', 'c', '-b', 'alfred.mem']);
      expect(code, 0);
      expect(out.text, contains('body of a'));
      expect(out.text, contains('body of b'));
      expect(out.text, contains('body of c'));
    });
  });

  group('walk — variadic, min one', () {
    test('zero entry points is refused as usage — walk has nowhere to '
        'start', () async {
      final out = _Out();
      final diag = _Out();
      final cli = Mem(
        vantage: site.root.path,
        out: out,
        diagnostics: diag,
        environment: const {},
      );
      final code = await cli.call(['walk', '-b', 'alfred.mem']);
      expect(code, 2);
      expect(diag.text, contains('<entry> is required'));
    });

    test('one entry point walks from it', () async {
      final root = materialize('alfred.mem');
      File(p.join(root.path, 'a.md')).writeAsStringSync(Page(
        topic: 'a',
        fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
        body: 'body of a',
      ).serialize());
      final out = _Out();
      final diag = _Out();
      final cli = Mem(
        vantage: site.root.path,
        out: out,
        diagnostics: diag,
        environment: const {},
      );
      final code = await cli.call(['walk', 'mem://alfred.mem/a', '-b', 'alfred.mem']);
      expect(code, 0);
      expect(out.text, contains('body of a'));
    });

    test('many entry points walk from all of them', () async {
      final root = materialize('alfred.mem');
      for (final topic in ['a', 'b']) {
        File(p.join(root.path, '$topic.md')).writeAsStringSync(Page(
          topic: topic,
          fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
          body: 'body of $topic',
        ).serialize());
      }
      final out = _Out();
      final diag = _Out();
      final cli = Mem(
        vantage: site.root.path,
        out: out,
        diagnostics: diag,
        environment: const {},
      );
      final code = await cli
          .call(['walk', 'mem://alfred.mem/a', 'mem://alfred.mem/b', '-b', 'alfred.mem']);
      expect(code, 0);
      expect(out.text, contains('body of a'));
      expect(out.text, contains('body of b'));
    });
  });

  group('exact-one verbs — remember, forget', () {
    test('remember with a surplus positional is refused, not silently '
        'dropped', () async {
      final out = _Out();
      final diag = _Out();
      final cli = Mem(
        vantage: site.root.path,
        out: out,
        diagnostics: diag,
        environment: const {},
      );
      materialize('alfred.mem');
      final code = await cli.call([
        'remember',
        'a',
        'surplus',
        '-b',
        'alfred.mem',
        ...signed,
        '-t',
        'semantic',
        '-A',
        '0.5',
        '-f',
        '/nonexistent',
      ]);
      expect(code, 2);
      expect(diag.text, contains('unexpected argument(s): surplus'));
    });

    test('forget with a surplus positional is refused, not silently '
        'dropped', () async {
      final root = materialize('alfred.mem');
      File(p.join(root.path, 'a.md')).writeAsStringSync(Page(
        topic: 'a',
        fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
        body: 'body of a',
      ).serialize());
      final out = _Out();
      final diag = _Out();
      final cli = Mem(
        vantage: site.root.path,
        out: out,
        diagnostics: diag,
        environment: const {},
      );
      final code =
          await cli.call(['forget', 'a', 'surplus', '-b', 'alfred.mem', ...signed]);
      expect(code, 2);
      expect(diag.text, contains('unexpected argument(s): surplus'));
    });
  });
}
