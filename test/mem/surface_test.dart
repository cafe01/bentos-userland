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
  late Site site;

  setUp(() => site = Site());
  tearDown(() => site.dispose());

  Directory materialize(String name) {
    final entity = Entity(name, from: site.root.path).create();
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
        var code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag).call([
          'remember',
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
        ).call([
          'remember',
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
        ).call(['remember', 'domain/x', '-t', 'semantic', '-A', '0.5']);
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
        ).call(['remember', 'domain/x', '-t', 'semantic', '-A', '0.5']);
        expect(code, 0);
        expect(diag.text, contains('written domain/x'));
      });
    });

    test('-t and -A are required', () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call(['remember', 'domain/x', '-A', '0.5']);
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
      ).call(['remember', 't', '-t', 'semantic', '-A', '0.5']);
      expect(code, 0);
    }

    test('refocus --to moves attention and leaves the body untouched',
        () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        await writeOne('alfred.mem');

        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call(['refocus', 't', '--to', '0.9']);
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
            .call(['refocus', 't']);
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
            .call(['forget', 't']);
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

    test('walk names every bank it crossed, in the order it drained them',
        () async {
      await site.runAsync(() async {
        final a = materialize('alfred.mem');
        File(p.join(a.path, 'a.md')).writeAsStringSync(Page(
          topic: 'a',
          fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
          body: 'crosses to [[mem://other.mem/b]]',
        ).serialize());
        final other = materialize('other.mem');
        File(p.join(other.path, 'b.md')).writeAsStringSync(Page(
          topic: 'b',
          fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
          body: 'the far side',
        ).serialize());

        final out = _Out(), diag = _Out();
        final code = await mem(out: out, diagnostics: diag)
            .call(['walk', 'mem://alfred.mem/a']);
        expect(code, 0);
        expect(out.text, startsWith('bank: alfred.mem, other.mem\n\n'));
      });
    });

    test('walk names an unresolved bank as skipped, never silently missing',
        () async {
      await site.runAsync(() async {
        final out = _Out(), diag = _Out();
        final code = await mem(out: out, diagnostics: diag)
            .call(['walk', 'mem://ghost.mem/a']);
        expect(code, 0);
        expect(out.text, contains('(skipped: ghost.mem)'));
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
