import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:bentos_userland/src/mem/attention.dart';
import 'package:bentos_userland/src/mem/page.dart';
import 'package:bentos_userland/src/mem/surface.dart';
import 'package:bentos_userland/src/mem/writer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../entity/helpers.dart';

/// A [GistSource] double: always answers with the body's own length, never
/// reaches a model. Deterministic, and never null — a surface test that
/// wants [RefusedWithoutModel] omits [gistSource] entirely instead.
final class _FixedGist implements GistSource {
  const _FixedGist();
  @override
  Future<String?> derive(String body) async => 'gist of ${body.length} chars';
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
  /// Who is writing, where the fixture's subject is not who wrote.
  ///
  /// Stated at the call, exactly as a hand would have to: `mem` derives an
  /// identity from nothing, so a fixture that omitted this would be testing a
  /// door that no longer opens.
  const memSigned = ['--actor', 'Tester <tester@test.local>'];

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

  Mem mem({
    String? bankEnv,
    GistSource? gistSource,
    required _Out out,
    required _Out diagnostics,
    Future<String> Function()? stdinReader,
    Future<String> Function(String)? fileReader,
  }) =>
      Mem(
        vantage: site.root.path,
        out: out,
        diagnostics: diagnostics,
        environment: bankEnv == null ? const {} : {'BENTOS_AGENT': bankEnv},
        gistSource: gistSource,
        stdinReader: stdinReader,
        fileReader: fileReader,
      );

  group('bank resolution', () {
    test('a bank not found from the vantage exits 1 and names the vantage',
        () async {
      await site.runAsync(() async {
        final out = _Out(), diag = _Out();
        final code = await mem(out: out, diagnostics: diag)
            .call(['-b', 'nobody.mem', 'survey']);
        expect(code, 1);
        expect(diag.text, contains('nobody.mem not found'));
        expect(diag.text, contains(site.root.path));
      });
    });

    test('no -b and no \$BENTOS_AGENT is a usage fault naming both cures',
        () async {
      await site.runAsync(() async {
        final out = _Out(), diag = _Out();
        final code = await mem(out: out, diagnostics: diag).call(['survey']);
        expect(code, 2);
        expect(diag.text, contains('-b <bank>'));
        expect(diag.text, contains(r'$BENTOS_AGENT'));
      });
    });

    test('\$BENTOS_AGENT supplies the bank when -b is omitted', () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call(['survey']);
        expect(code, 0);
        expect(diag.text, contains('alfred.mem'));
      });
    });
  });

  group('remember and recall', () {
    test('remember with --gist lands, and recall reads it back', () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        var out = _Out(), diag = _Out();
        var code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag).call([...memSigned, 'remember',
          'domain/hello',
          '-t',
          'semantic',
          '-A',
          '0.7',
          '--gist',
          'a greeting',
        ], );
        // body from stdin: none piped in this test, so remember needs -f or
        // stdin — exercised in the file/stdin group below. This call must
        // therefore refuse on a missing body, not on the gist.
        expect(code, 2);
        expect(diag.text, contains('the body is required'));
      });
    });

    test('remember -f <path>, then recall renders it back with its title line',
        () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        final bodyFile = File(p.join(site.root.path, 'body.txt'))
          ..writeAsStringSync('World.');
        var out = _Out(), diag = _Out();
        final code = await mem(
          bankEnv: 'alfred.mem',
          out: out,
          diagnostics: diag,
          fileReader: (path) => File(path).readAsString(),
        ).call([...memSigned, 'remember',
          'domain/hello',
          '-t',
          'semantic',
          '-A',
          '0.7',
          '-f',
          bodyFile.path,
          '--gist',
          'a greeting',
        ]);
        expect(code, 0);
        expect(diag.text, contains('written domain/hello'));

        out = _Out();
        diag = _Out();
        final recallCode =
            await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
                .call(['recall', 'domain/hello']);
        expect(recallCode, 0);
        expect(out.text, contains('domain/hello'));
        expect(out.text, contains('semantic'));
        expect(out.text, contains('a:0.7'));
        expect(out.text, contains('World.'));
        expect(diag.text, contains('1 pages'));
      });
    });

    test('remember with no gist and no model refuses without landing',
        () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        final out = _Out(), diag = _Out();
        final code = await mem(
          bankEnv: 'alfred.mem',
          out: out,
          diagnostics: diag,
          stdinReader: () async => 'a body',
        ).call([...memSigned, 'remember', 'domain/x', '-t', 'semantic', '-A', '0.5']);
        expect(code, 1);
        expect(diag.text, contains('refused'));
        expect(diag.text, contains('no gist'));
      });
    });

    test('remember derives a gist through the injected seam when none is given',
        () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        final out = _Out(), diag = _Out();
        final code = await mem(
          bankEnv: 'alfred.mem',
          out: out,
          diagnostics: diag,
          gistSource: const _FixedGist(),
          stdinReader: () async => 'a body',
        ).call([...memSigned, 'remember', 'domain/x', '-t', 'semantic', '-A', '0.5']);
        expect(code, 0);
        expect(diag.text, contains('written domain/x'));
      });
    });

    test('-t and -A are required', () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call([...memSigned, 'remember', 'domain/x', '-A', '0.5']);
        expect(code, 2);
        expect(diag.text, contains('-t <type>'));
      });
    });
  });

  group('empty reach', () {
    test('survey with no pages exits 0 and echoes the reach', () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call(['survey', '--hot']);
        expect(code, 0);
        expect(diag.text, contains('no pages under --hot'));
        expect(out.text, equals('bank: alfred.mem\n\n'));
      });
    });
  });

  group('refocus, gist, forget', () {
    Future<void> writeOne(String bank) async {
      final out = _Out(), diag = _Out();
      final code = await mem(
        bankEnv: bank,
        out: out,
        diagnostics: diag,
        stdinReader: () async => 'body text here',
        gistSource: const _FixedGist(),
      ).call([...memSigned, 'remember', 't', '-t', 'semantic', '-A', '0.5']);
      expect(code, 0);
    }

    test('refocus --to moves attention and leaves the body untouched',
        () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        await writeOne('alfred.mem');

        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call([...memSigned, 'refocus', 't', '--to', '0.9']);
        expect(code, 0);
        expect(diag.text, contains('written t'));
      });
    });

    test('refocus refuses when neither or both of --to/--by are given',
        () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        await writeOne('alfred.mem');
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call([...memSigned, 'refocus', 't']);
        expect(code, 2);
        expect(diag.text, contains('--to'));
      });
    });

    test('forget removes the page — recall then finds nothing', () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        await writeOne('alfred.mem');

        var out = _Out(), diag = _Out();
        var code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call([...memSigned, 'forget', 't']);
        expect(code, 0);

        out = _Out();
        diag = _Out();
        code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call(['recall', 't']);
        expect(code, 0);
        expect(diag.text, contains('no pages under t'));
      });
    });
  });

  group('recall — many topics', () {
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

    test('many topics, all found — rendered in the order named, not resorted',
        () async {
      await site.runAsync(() async {
        seed('alfred.mem', ['a', 'b', 'c']);
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call(['recall', 'c', 'a', 'b']);
        expect(code, 0);
        final ia = out.text.indexOf('body of a');
        final ib = out.text.indexOf('body of b');
        final ic = out.text.indexOf('body of c');
        expect(ic, lessThan(ia));
        expect(ia, lessThan(ib));
        expect(diag.text, contains('3 pages'));
      });
    });

    test('partial miss renders the found pages and names the missing ones',
        () async {
      await site.runAsync(() async {
        seed('alfred.mem', ['a', 'b']);
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call(['recall', 'a', 'ghost', 'b']);
        expect(code, 0);
        expect(out.text, contains('body of a'));
        expect(out.text, contains('body of b'));
        expect(diag.text, contains('2 pages'));
        expect(diag.text, contains('no page found for: ghost'));
      });
    });

    test('total miss names every topic asked for, exits as today', () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call(['recall', 'ghost1', 'ghost2']);
        expect(code, 0);
        expect(diag.text, contains('no pages under ghost1, ghost2'));
        expect(out.text, equals('bank: alfred.mem\n\n'));
      });
    });

    test('a repeated topic is deduped silently, not an error', () async {
      await site.runAsync(() async {
        seed('alfred.mem', ['a']);
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call(['recall', 'a', 'a']);
        expect(code, 0);
        expect('body of a'.allMatches(out.text).length, 1);
        expect(diag.text, contains('1 pages'));
      });
    });

    test('no positionals, flags only — unchanged selector-only reach',
        () async {
      await site.runAsync(() async {
        seed('alfred.mem', ['a', 'b']);
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call(['recall', '--cool']);
        expect(code, 0);
        expect(out.text, contains('body of a'));
        expect(out.text, contains('body of b'));
        expect(diag.text, contains('2 pages'));
      });
    });
  });

  group('walk', () {
    test('an entry point with no links returns just itself, body form',
        () async {
      await site.runAsync(() async {
        final root = materialize('alfred.mem');
        File(p.join(root.path, 'a.md')).writeAsStringSync(Page(
          topic: 'a',
          fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
          body: 'hello',
        ).serialize());

        final out = _Out(), diag = _Out();
        final code = await mem(out: out, diagnostics: diag)
            .call(['walk', 'mem://alfred.mem/a']);
        expect(code, 0);
        expect(out.text, contains('hello'));
        expect(diag.text, contains('1 pages'));
      });
    });

    test('an unresolved bank is skipped and reported, never fails the walk',
        () async {
      await site.runAsync(() async {
        final out = _Out(), diag = _Out();
        final code = await mem(out: out, diagnostics: diag)
            .call(['walk', 'mem://ghost.mem/a']);
        expect(code, 0);
        expect(diag.text, contains('skipped mem://ghost.mem/a'));
        expect(diag.text, contains('bankNotFound'));
      });
    });
  });

  group('bank header — R5.7, every response names its bank', () {
    test('survey opens with the bank it answered from', () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call(['survey']);
        expect(code, 0);
        expect(out.text, startsWith('bank: alfred.mem\n\n'));
      });
    });

    test('recall opens with the bank it answered from', () async {
      await site.runAsync(() async {
        final root = materialize('alfred.mem');
        File(p.join(root.path, 'a.md')).writeAsStringSync(Page(
          topic: 'a',
          fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
          body: 'hello',
        ).serialize());
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call(['recall', 'a']);
        expect(code, 0);
        expect(out.text, startsWith('bank: alfred.mem\n\n'));
      });
    });

    test('health opens with the bank it answered from', () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call(['health']);
        expect(code, 0);
        expect(out.text, startsWith('bank: alfred.mem\n\n'));
      });
    });

  });

  group('the composed form — a walk renders a document, not a report', () {
    /// The healthy page a composition is made of: hot, light, ordinary age,
    /// nothing marked. Its fence must be silent.
    void writeHot(Directory bank, String topic, String body) {
      File(p.join(bank.path, '$topic.md')).writeAsStringSync(Page(
        topic: topic,
        fields: Fields(type: MemType.semantic, attention: Attention(1.0)),
        body: body,
      ).serialize());
    }

    test('a page is fenced by its address, and a healthy page says nothing more',
        () async {
      await site.runAsync(() async {
        final a = materialize('alfred.mem');
        writeHot(a, 'you', 'You exist.');

        final out = _Out(), diag = _Out();
        final code = await mem(out: out, diagnostics: diag)
            .call(['walk', 'mem://alfred.mem/you']);
        expect(code, 0);
        expect(out.text, '┌─ you\nYou exist.\n└─ you\n');
      });
    });

    test('no bank banner, no ruler — nothing precedes the first page', () async {
      await site.runAsync(() async {
        final a = materialize('alfred.mem');
        writeHot(a, 'you', 'You exist.');

        final out = _Out(), diag = _Out();
        await mem(out: out, diagnostics: diag).call(['walk', 'mem://alfred.mem/you']);
        expect(out.text, startsWith('┌─'));
        expect(out.text, isNot(contains('bank:')));
        expect(out.text, isNot(contains('─────')));
      });
    });

    test('a page reached in a foreign bank carries its full address', () async {
      await site.runAsync(() async {
        final a = materialize('alfred.mem');
        writeHot(a, 'a', 'crosses to [[mem://other.mem/b]]');
        final other = materialize('other.mem');
        writeHot(other, 'b', 'the far side');

        final out = _Out(), diag = _Out();
        final code = await mem(out: out, diagnostics: diag)
            .call(['walk', 'mem://alfred.mem/a']);
        expect(code, 0);
        expect(out.text, contains('┌─ a\n'));
        expect(out.text, contains('┌─ mem://other.mem/b\n'));
        expect(out.text, contains('└─ mem://other.mem/b\n'));
      });
    });

    test('an unresolved bank never enters the composition — the skip is a diagnostic',
        () async {
      await site.runAsync(() async {
        final out = _Out(), diag = _Out();
        final code = await mem(out: out, diagnostics: diag)
            .call(['walk', 'mem://ghost.mem/a']);
        expect(code, 0);
        expect(out.text, isEmpty);
        expect(diag.text, contains('skipped mem://ghost.mem/a'));
      });
    });

    test('vitals speak only where the page is not the healthy state', () async {
      await site.runAsync(() async {
        final a = materialize('alfred.mem');
        File(p.join(a.path, 'a.md')).writeAsStringSync(Page(
          topic: 'a',
          fields: Fields(
            type: MemType.semantic,
            attention: Attention(0.4),
            tags: ['suspect-stale'],
            modified: DateTime.now(),
          ),
          body: List.filled(400, 'word').join(' '),
        ).serialize());

        final out = _Out(), diag = _Out();
        final code = await mem(out: out, diagnostics: diag)
            .call(['walk', 'mem://alfred.mem/a']);
        expect(code, 0);
        final close = out.text.split('\n').firstWhere((l) => l.startsWith('└─'));
        expect(close, contains('cool'));
        expect(close, contains('400w'));
        expect(close, contains('old'));
        expect(close, contains('#suspect-stale'));
      });
    });
  });

  group('health', () {
    test('a page with no inbound edge is an orphan', () async {
      await site.runAsync(() async {
        final root = materialize('alfred.mem');
        File(p.join(root.path, 'a.md')).writeAsStringSync(Page(
          topic: 'a',
          fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
          body: 'lonely',
        ).serialize());

        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call(['health']);
        expect(code, 0);
        expect(out.text, contains('orphans (1)'));
        expect(out.text, contains('a'));
        expect(diag.text, contains('external links unjudged'));
      });
    });
  });
}
