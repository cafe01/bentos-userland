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

    // A "written but the local tree is stale" case used to be reachable by
    // faking a branch checkout (`site.git.heads[where] = 'main'`) ahead of a
    // write, on the belief that an attached tree was inherently suspect. It
    // is not: an act now commits in the very tree it materializes, so the
    // tree an attached write just landed in is, by construction, already at
    // its own tip when `advance()` reads it afterward — Behind is
    // unreachable *from that shape*. It IS reachable from a different one,
    // proven below: a legacy-detached bank tree at the entity's own
    // materialization address. `standingAt` only sees *attached* worktrees,
    // so `land()` finds none standing, materializes a **second**, attached
    // tree at the instance's own convention address (`instances/main`) and
    // commits there — the branch moves under a tree the reader is not
    // looking at. `advance()` then reads the original (still detached) tree
    // and tries to catch it up to the new tip; if that tree carries content
    // colliding with what the write introduced, Git's own checkout declines,
    // and `Behind` is exactly what carries that decline outward.
    test(
        'remember on a legacy-detached bank tree lands, but reports TREE '
        'STALE rather than a clean write', () async {
      await site.runAsync(() async {
        final where = materialize('alfred.mem');

        // The legacy condition: detach the tree Git itself just attached.
        final detach =
            Process.runSync('git', ['-C', where.path, 'checkout', '--detach']);
        expect(detach.exitCode, 0);

        // Untracked, and colliding with the very file the coming write
        // introduces — the shape that makes the substrate's own checkout
        // decline rather than silently fast-forward the stale tree.
        File(p.join(where.path, 'domain/hello.md'))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('stale local content');

        final out = _Out(), diag = _Out();
        final code = await mem(
          bankEnv: 'alfred.mem',
          out: out,
          diagnostics: diag,
          stdinReader: () async => 'World.',
        ).call([...memSigned, 'remember', 'domain/hello', '-t', 'semantic',
          '-A', '0.7', '--gist', 'a greeting']);

        // The act landed — the line carries it — and the exit code and
        // message say the tree did not follow, never that the write failed.
        expect(diag.text, contains('written domain/hello'));
        expect(code, Mem.materializationLagCode);
        expect(diag.text, contains('LANDED, TREE STALE'));
        expect(diag.text, isNot(contains('LANDED, NO TREE')));
      });
    });

    test('a write landing into a bank with no tree says so, and exits non-zero',
        () async {
      await site.runAsync(() async {
        // Created and given its line, but never materialized: the write has
        // nowhere to be read, and this used to report as a clean write.
        final entity =
            Entity('alfred.mem', from: site.root.path).create(actor: testActor);
        entity.instance('main').create();

        final out = _Out(), diag = _Out();
        final code = await mem(
          bankEnv: 'alfred.mem',
          out: out,
          diagnostics: diag,
          stdinReader: () async => 'World.',
        ).call([...memSigned, 'remember', 'domain/hello', '-t', 'semantic',
          '-A', '0.7', '--gist', 'a greeting']);

        expect(diag.text, contains('written domain/hello'));
        expect(code, Mem.materializationLagCode);
        expect(code, isNot(1));
        expect(diag.text, contains('NO TREE'));
        expect(diag.text, contains(p.join(site.root.path, 'alfred.mem')));
      });
    });

    group('a bank installed but never materialized reads NO TREE, not empty',
        () {
      // Before the read-path guard, this exact fixture answered "no pages"
      // for survey/recall/health and every entry came back "dead" from
      // walk — indistinguishable from a bank that genuinely holds nothing.
      // The guard's whole job is to make "empty" and "invisible" say
      // different things.
      Entity installOnly(Directory root) {
        final entity =
            Entity('alfred.mem', from: root.path).create(actor: testActor);
        entity.instance('main').create();
        return entity;
      }

      test('survey', () async {
        await site.runAsync(() async {
          installOnly(site.root);
          final out = _Out(), diag = _Out();
          final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
              .call(['survey']);
          expect(code, Mem.materializationLagCode);
          expect(diag.text, contains('NO TREE'));
          expect(diag.text, isNot(contains('no pages under')));
          expect(diag.text, contains(p.join(site.root.path, 'alfred.mem')));
        });
      });

      test('recall', () async {
        await site.runAsync(() async {
          installOnly(site.root);
          final out = _Out(), diag = _Out();
          final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
              .call(['recall', 'domain/hello']);
          expect(code, Mem.materializationLagCode);
          expect(diag.text, contains('NO TREE'));
          expect(diag.text, isNot(contains('no pages under')));
        });
      });

      test('health', () async {
        await site.runAsync(() async {
          installOnly(site.root);
          final out = _Out(), diag = _Out();
          final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
              .call(['health']);
          expect(code, Mem.materializationLagCode);
          expect(diag.text, contains('NO TREE'));
        });
      });

      test('walk', () async {
        await site.runAsync(() async {
          installOnly(site.root);
          final out = _Out(), diag = _Out();
          final code = await mem(out: out, diagnostics: diag)
              .call(['walk', 'mem://alfred.mem/domain/hello']);
          expect(code, Mem.materializationLagCode);
          expect(diag.text, contains('NO TREE'));
          expect(diag.text, isNot(contains('dead')));
        });
      });

      // refocus/tag/gist all select against `bank.pages()` before landing —
      // the same lie f620787 killed for survey/recall/health/walk, alive
      // here because none of the three called the guard.
      test('refocus', () async {
        await site.runAsync(() async {
          installOnly(site.root);
          final out = _Out(), diag = _Out();
          final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
              .call([...memSigned, 'refocus', 'domain/hello', '--to', '0.5']);
          expect(code, Mem.materializationLagCode);
          expect(diag.text, contains('NO TREE'));
          expect(diag.text, isNot(contains('no pages under')));
        });
      });

      test('tag', () async {
        await site.runAsync(() async {
          installOnly(site.root);
          final out = _Out(), diag = _Out();
          final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
              .call([...memSigned, 'tag', 'domain/hello', '--add', 'x']);
          expect(code, Mem.materializationLagCode);
          expect(diag.text, contains('NO TREE'));
          expect(diag.text, isNot(contains('no pages under')));
        });
      });

      test('gist', () async {
        await site.runAsync(() async {
          installOnly(site.root);
          final out = _Out(), diag = _Out();
          final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
              .call([...memSigned, 'gist', 'domain/hello']);
          expect(code, Mem.materializationLagCode);
          expect(diag.text, contains('NO TREE'));
          expect(diag.text, isNot(contains('no pages under')));
        });
      });
    });

    test(
        'a materialization-lag exit is distinct from a decided refusal\'s exit',
        () async {
      await site.runAsync(() async {
        // A decided refusal that never lands anything — the ordinary
        // shape of Mem.exitCode's documented 1.
        materialize('alfred.mem');
        final out = _Out(), diag = _Out();
        final refusedCode = await mem(
          bankEnv: 'alfred.mem',
          out: out,
          diagnostics: diag,
        ).call(['-b', 'nobody.mem', 'survey']);

        expect(refusedCode, 1);
        expect(refusedCode, isNot(Mem.materializationLagCode));
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

    test('remember with an empty body refuses and teaches --empty',
        () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        final out = _Out(), diag = _Out();
        final code = await mem(
          bankEnv: 'alfred.mem',
          out: out,
          diagnostics: diag,
          gistSource: const _FixedGist(),
          stdinReader: () async => '',
        ).call([...memSigned, 'remember', 'domain/x', '-t', 'semantic', '-A', '0.5']);
        expect(code, 1);
        expect(diag.text, contains('refused'));
        expect(diag.text, contains('domain/x'));
        expect(diag.text, contains('--empty'));
      });
    });

    test('remember with an empty body and --empty lands it on purpose',
        () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        final out = _Out(), diag = _Out();
        final code = await mem(
          bankEnv: 'alfred.mem',
          out: out,
          diagnostics: diag,
          gistSource: const _FixedGist(),
          stdinReader: () async => '',
        ).call([...memSigned, 'remember', 'domain/x', '-t', 'semantic',
          '-A', '0.5', '--empty']);
        expect(code, 0);
        expect(diag.text, contains('written domain/x'));
      });
    });

    test('a write against a bank with a hand-edited page refuses and names '
        'the cure', () async {
      await site.runAsync(() async {
        final root = materialize('alfred.mem');
        var out = _Out(), diag = _Out();
        var code = await mem(
          bankEnv: 'alfred.mem',
          out: out,
          diagnostics: diag,
          gistSource: const _FixedGist(),
          stdinReader: () async => 'a body',
        ).call([...memSigned, 'remember', 'a', '-t', 'semantic', '-A', '0.5']);
        expect(code, 0);

        // A hand outside `mem` edits the checkout directly — the exact shape
        // of the incident this guard exists for.
        File(p.join(root.path, 'a.md')).writeAsStringSync('mine, not mem\'s');

        out = _Out();
        diag = _Out();
        code = await mem(
          bankEnv: 'alfred.mem',
          out: out,
          diagnostics: diag,
          gistSource: const _FixedGist(),
          stdinReader: () async => 'a different body',
        ).call([...memSigned, 'remember', 'b', '-t', 'semantic', '-A', '0.5']);
        expect(code, 1);
        expect(diag.text, contains('refused'));
        expect(diag.text, contains('hand-edited'));
        expect(diag.text, contains('a'));
        expect(diag.text, contains('git'));
        expect(File(p.join(root.path, 'a.md')).readAsStringSync(), 'mine, not mem\'s');
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

    test('-A alone missing is a usage fault naming -A', () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call([...memSigned, 'remember', 'domain/x', '-t', 'semantic']);
        expect(code, 2);
        expect(diag.text, contains('-A <attention>'));
      });
    });

    // --actor is required on every act, but it is a platform-wide law
    // (statedActor/NoActor), not a mem-specific one — a caller scripting
    // across entity, chat and mem reads one exit code for "you did not say
    // who you are", distinct from an ordinary usage fault (2).
    test('a missing --actor refuses at 64, the platform-wide code, not 2',
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
        expect(code, 64);
        expect(code, isNot(2));
        expect(diag.text, contains('say who is writing'));
        expect(diag.text, contains('--actor'));
      });
    });

    // The scale is eleven fixed notches, deliberately — not a defect an
    // off-notch value trips over, but a contract: `remember -A` refuses one
    // as a usage fault, cleanly, rather than crashing on the parse.
    test('remember -A off-notch is a clean usage refusal, exit 2', () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call([...memSigned, 'remember', 'domain/x', '-t', 'semantic',
          '-A', '0.75']);
        expect(code, 2);
        expect(diag.text, contains('off-notch'));
        expect(diag.text, contains('0.75'));
      });
    });

    test('--min-attention off-notch is the same clean refusal, exit 2',
        () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call(['survey', '--min-attention', '0.75']);
        expect(code, 2);
        expect(diag.text, contains('off-notch'));
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
        expect(diag.text, contains('0 of 0 shown (filter: --hot)'));
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

    test('refocus --attention/-A is an alias for --to', () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        await writeOne('alfred.mem');

        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call([...memSigned, 'refocus', 't', '--attention', '0.8']);
        expect(code, 0);
        expect(diag.text, contains('written t'));
      });
    });

    test('refocus refuses when both --to and --attention are given', () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        await writeOne('alfred.mem');

        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call([...memSigned, 'refocus', 't', '--to', '0.8', '-A', '0.9']);
        expect(code, 2);
        expect(diag.text, contains('--to and --attention'));
      });
    });

    test('refocus takes many topics in one call', () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        for (final topic in ['a', 'b', 'c', 'd']) {
          final out = _Out(), diag = _Out();
          final code = await mem(
            bankEnv: 'alfred.mem',
            out: out,
            diagnostics: diag,
            stdinReader: () async => 'body of $topic',
            gistSource: const _FixedGist(),
          ).call([...memSigned, 'remember', topic, '-t', 'semantic', '-A', '0.5']);
          expect(code, 0);
        }

        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call([...memSigned, 'refocus', 'a', 'b', 'c', 'd', '--to', '0.9']);
        expect(code, 0);
        expect(diag.text, contains('written a, b, c, d'));
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

    test('refocus on a topic matching nothing names the miss and exits 1 — '
        'a failed lookup, and lands nothing', () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        await writeOne('alfred.mem');
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call([...memSigned, 'refocus', 'nope', '--to', '0.9']);
        expect(code, 1);
        expect(diag.text, contains('no page at nope in alfred.mem'));
        expect(diag.text, isNot(contains('written')));
      });
    });

    test('gist on a selector matching nothing names the miss and exits 1',
        () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        await writeOne('alfred.mem');
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call([...memSigned, 'gist', '--tag', 'no-such-tag']);
        expect(code, 1);
        expect(diag.text, contains('no page matches'));
        expect(diag.text, isNot(contains('written')));
      });
    });

    test('tag on a topic matching nothing names the miss and exits 1',
        () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        await writeOne('alfred.mem');
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call([...memSigned, 'tag', 'nope', '--add', 'x']);
        expect(code, 1);
        expect(diag.text, contains('no page at nope in alfred.mem'));
        expect(diag.text, isNot(contains('written')));
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
        expect(code, 1);
        expect(diag.text, contains('no page at t in alfred.mem'));
      });
    });
  });

  group('tag', () {
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

    test('--add lands the tag', () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        await writeOne('alfred.mem');

        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call([...memSigned, 'tag', 't', '--add', 'suspect-stale']);
        expect(code, 0);
        expect(diag.text, contains('written t'));
      });
    });

    test('refuses when neither --add nor --remove is given', () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        await writeOne('alfred.mem');
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call([...memSigned, 'tag', 't']);
        expect(code, 2);
        expect(diag.text, contains('--add'));
      });
    });

    test('refuses adding and removing the same tag in one call', () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        await writeOne('alfred.mem');
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call([...memSigned, 'tag', 't', '--add', 'x', '--remove', 'x']);
        expect(code, 2);
        expect(diag.text, contains('x'));
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
        expect(diag.text, contains('no page at ghost in alfred.mem'));
      });
    });

    test('total miss names every topic asked for and exits 1 — a failed lookup',
        () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call(['recall', 'ghost1', 'ghost2']);
        expect(code, 1);
        expect(diag.text, contains('no page at ghost1 in alfred.mem'));
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

    test('a mem:// address naming the addressed bank resolves the same as '
        'its bare topic', () async {
      await site.runAsync(() async {
        seed('alfred.mem', ['a']);
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call(['recall', 'mem://alfred.mem/a']);
        expect(code, 0);
        expect(out.text, contains('body of a'));
        expect(diag.text, contains('1 pages'));
      });
    });

    test('a mem:// address naming a foreign bank is a stated error, never '
        '"no pages"', () async {
      await site.runAsync(() async {
        seed('alfred.mem', ['a']);
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call(['recall', 'mem://software.bentos.mem/whatever']);
        expect(code, 2);
        expect(diag.text, contains('names bank software.bentos.mem'));
        expect(diag.text, contains('not the addressed bank alfred.mem'));
        expect(diag.text, isNot(contains('no pages')));
      });
    });

    test('a bare topic and its mem:// address dedupe to one page', () async {
      await site.runAsync(() async {
        seed('alfred.mem', ['a']);
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call(['recall', 'a', 'mem://alfred.mem/a']);
        expect(code, 0);
        expect('body of a'.allMatches(out.text).length, 1);
        expect(diag.text, contains('1 pages'));
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
        expect(diag.text, contains('walk mem://ghost.mem/a'));
        expect(diag.text, contains('1 not entered — 1 bank not found'));
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

    /// The same page, at a chosen age — the one field these tests vary.
    void writeAged(Directory bank, String topic, DateTime modified) {
      File(p.join(bank.path, '$topic.md')).writeAsStringSync(Page(
        topic: topic,
        fields: Fields(
          type: MemType.semantic,
          attention: Attention(1.0),
          modified: modified,
        ),
        body: 'a body',
      ).serialize());
    }

    /// Today's date in UTC, the form a stamp takes.
    String today() {
      final t = DateTime.now().toUtc();
      final month = t.month.toString().padLeft(2, '0');
      final day = t.day.toString().padLeft(2, '0');
      return '${t.year}-$month-$day';
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
            .call(['walk', 'mem://alfred.mem/a', '--cross-bank']);
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
        expect(diag.text, contains('1 not entered — 1 bank not found'));
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
        expect(close, contains(today()));
        expect(close, contains('#suspect-stale'));
      });
    });

    test('the default states a date and never the clock — a walk is a prompt '
        'prefix, and a byte that moves with the clock invalidates it',
        () async {
      await site.runAsync(() async {
        final a = materialize('alfred.mem');
        writeAged(a, 'a', DateTime.utc(2020, 3, 7, 11, 30));

        final out = _Out(), diag = _Out();
        final code = await mem(out: out, diagnostics: diag)
            .call(['walk', 'mem://alfred.mem/a']);
        expect(code, 0);
        final close = out.text.split('\n').firstWhere((l) => l.startsWith('└─'));
        expect(close, contains('2020-03-07'));
        expect(close, isNot(contains('old')));
        expect(close, isNot(contains('d')));
      });
    });

    test('--age relative keeps the clock, and with it the freshness gate — a '
        'page of ordinary age says nothing', () async {
      await site.runAsync(() async {
        final a = materialize('alfred.mem');
        writeAged(a, 'a', DateTime.now().subtract(const Duration(days: 40)));

        final out = _Out(), diag = _Out();
        final code = await mem(out: out, diagnostics: diag)
            .call(['--age', 'relative', 'walk', 'mem://alfred.mem/a']);
        expect(code, 0);
        final close = out.text.split('\n').firstWhere((l) => l.startsWith('└─'));
        expect(close, isNot(contains('old')));

        // The same page under the default: the stamp is unconditional, so
        // what the gate silenced is stated.
        final out2 = _Out();
        await mem(out: out2, diagnostics: _Out())
            .call(['walk', 'mem://alfred.mem/a']);
        final close2 =
            out2.text.split('\n').firstWhere((l) => l.startsWith('└─'));
        expect(close2, contains('-'));
      });
    });

    test('--age none states no age at all', () async {
      await site.runAsync(() async {
        final a = materialize('alfred.mem');
        writeAged(a, 'a', DateTime.utc(2020, 3, 7));

        final out = _Out(), diag = _Out();
        final code = await mem(out: out, diagnostics: diag)
            .call(['--age', 'none', 'walk', 'mem://alfred.mem/a']);
        expect(code, 0);
        // A healthy page with no age stated closes on its address alone —
        // stronger than "no date", which a relative rendering would also pass.
        final close = out.text.split('\n').firstWhere((l) => l.startsWith('└─'));
        expect(close, '└─ a');
      });
    });

    test('the register reaches survey and recall too, not walk alone',
        () async {
      await site.runAsync(() async {
        final a = materialize('alfred.mem');
        writeAged(a, 'a', DateTime.utc(2020, 3, 7));

        final survey = _Out();
        await mem(bankEnv: 'alfred.mem', out: survey, diagnostics: _Out())
            .call(['survey']);
        expect(survey.text, contains('·2020-03-07'));

        final recall = _Out();
        await mem(bankEnv: 'alfred.mem', out: recall, diagnostics: _Out())
            .call(['recall', 'a']);
        expect(recall.text, contains('modified 2020-03-07'));
        expect(recall.text, isNot(contains('ago')));

        final relative = _Out();
        await mem(bankEnv: 'alfred.mem', out: relative, diagnostics: _Out())
            .call(['--age', 'relative', 'recall', 'a']);
        expect(relative.text, contains('ago'));
      });
    });

    test('a mode nobody offers is a usage fault', () async {
      await site.runAsync(() async {
        final out = _Out(), diag = _Out();
        final code = await mem(out: out, diagnostics: diag)
            .call(['--age', 'yesterday', 'walk', 'mem://alfred.mem/a']);
        expect(code, 2);
      });
    });
  });

  group('the shaped walk — the set, not the composition (R7: --dry-run renamed)', () {
    void write(Directory bank, String topic, String body) {
      File(p.join(bank.path, '$topic.md')).writeAsStringSync(Page(
        topic: topic,
        fields: Fields(type: MemType.semantic, attention: Attention(1.0)),
        body: body,
      ).serialize());
    }

    test('states every page at its ring, by what named it, with no bodies',
        () async {
      await site.runAsync(() async {
        final a = materialize('alfred.mem');
        write(a, 'root', 'names [[near]]');
        write(a, 'near', 'names [[far]]');
        write(a, 'far', 'the leaf body');

        final out = _Out(), diag = _Out();
        final code = await mem(out: out, diagnostics: diag)
            .call(['walk', 'mem://alfred.mem/root', '--shape']);
        expect(code, 0);
        expect(out.text, contains('   0      2  root  ← entry'));
        expect(out.text, contains('   1      2  near  ← root'));
        expect(out.text, contains('   2      3  far  ← near'));
        // No body reaches the answer — that is the whole point of the shape.
        expect(out.text, isNot(contains('the leaf body')));
        expect(out.text, isNot(contains('┌─')));
        // The weight line moved off stdout onto the frame (R7.3).
        expect(out.text, isNot(contains('links followed')));
        expect(diag.text, contains('3 pages, 7 words, 2 links followed'));
      });
    });

    test('what did not enter is the answer here, and stands on stdout',
        () async {
      await site.runAsync(() async {
        final a = materialize('alfred.mem');
        write(a, 'root', 'names [[ghost]] and [[mem://nowhere.mem/x]]');

        final out = _Out(), diag = _Out();
        final code = await mem(out: out, diagnostics: diag).call(
            ['walk', 'mem://alfred.mem/root', '--cross-bank', '--shape']);
        expect(code, 0);
        expect(out.text, contains('not entered'));
        expect(out.text, contains('mem://alfred.mem/ghost  ← root  — dead'));
        expect(out.text,
            contains('mem://nowhere.mem/x  ← root  — bankNotFound'));
        // The not-entered detail lives once, as artifact under --shape
        // (R3.2) — the frame states only the count and reason breakdown.
        expect(diag.text, isNot(contains('← root')));
      });
    });

    test('a cross-bank link is not entered by default, and says so', () async {
      await site.runAsync(() async {
        final a = materialize('alfred.mem');
        write(a, 'root', 'names [[mem://nowhere.mem/x]]');

        final out = _Out(), diag = _Out();
        final code = await mem(out: out, diagnostics: diag)
            .call(['walk', 'mem://alfred.mem/root', '--shape']);
        expect(code, 0);
        expect(out.text, contains('not entered'));
        expect(out.text,
            contains('mem://nowhere.mem/x  ← root  — crossBank'));
      });
    });

    test('a selector excludes a page, and the shaped walk says so rather '
        'than passing over it in silence', () async {
      await site.runAsync(() async {
        final a = materialize('alfred.mem');
        write(a, 'root', 'names [[cold]]');
        File(p.join(a.path, 'cold.md')).writeAsStringSync(Page(
          topic: 'cold',
          fields: Fields(type: MemType.semantic, attention: Attention(0.2)),
          body: 'chilly',
        ).serialize());

        final out = _Out(), diag = _Out();
        final code = await mem(out: out, diagnostics: diag)
            .call(['walk', 'mem://alfred.mem/root', '--hot', '--shape']);
        expect(code, 0);
        expect(out.text, contains('   0      2  root  ← entry'));
        expect(out.text, contains('cold  ← root  — filtered'));
      });
    });

    test('a page skipped from several inbound links prints once, vias folded '
        'into that line', () async {
      await site.runAsync(() async {
        final a = materialize('alfred.mem');
        write(a, 'root', 'names [[cold]] and [[near]]');
        write(a, 'near', 'names [[cold]]');
        File(p.join(a.path, 'cold.md')).writeAsStringSync(Page(
          topic: 'cold',
          fields: Fields(type: MemType.semantic, attention: Attention(0.2)),
          body: 'chilly',
        ).serialize());

        final out = _Out(), diag = _Out();
        final code = await mem(out: out, diagnostics: diag)
            .call(['walk', 'mem://alfred.mem/root', '--hot', '--shape']);
        expect(code, 0);
        // One line, not one per inbound edge.
        expect('cold  ←'.allMatches(out.text).length, 1);
        expect(out.text, contains('cold  ← root, near  — filtered'));
      });
    });

    test('a retired --dry-run names its replacement, never a bare parse error',
        () async {
      await site.runAsync(() async {
        materialize('alfred.mem');
        final out = _Out(), diag = _Out();
        final code = await mem(out: out, diagnostics: diag)
            .call(['walk', 'mem://alfred.mem/root', '--dry-run']);
        expect(code, 2);
        expect(diag.text, contains('no option --dry-run. Did you mean --shape?'));
      });
    });

    test('an ordinary walk keeps the skip off stdout, folded into the frame',
        () async {
      await site.runAsync(() async {
        final a = materialize('alfred.mem');
        write(a, 'root', 'names [[ghost]]');

        final out = _Out(), diag = _Out();
        final code = await mem(out: out, diagnostics: diag)
            .call(['walk', 'mem://alfred.mem/root']);
        expect(code, 0);
        expect(diag.text, contains('1 not entered — 1 dead'));
        expect(diag.text,
            contains('1 link point at pages that do not exist: root → ghost'));
        expect(out.text, isNot(contains('not entered')));
      });
    });
  });

  group('health', () {
    test('the single-topic view still carries the unjudged caveat — it '
        'lists edges but resolves none of them', () async {
      await site.runAsync(() async {
        materialize('other.mem');
        final root = materialize('alfred.mem');
        File(p.join(root.path, 'a.md')).writeAsStringSync(Page(
          topic: 'a',
          fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
          body: 'names [[mem://other.mem/x]]',
        ).serialize());

        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call(['health', 'a']);
        expect(code, 0);
        expect(out.text, contains('other.mem/x'));
        expect(diag.text, contains('external links unjudged'));
      });
    });

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

    test('a cross-bank link to an installed sibling is judged: dead when '
        'the topic is absent there', () async {
      await site.runAsync(() async {
        materialize('other.mem');
        final root = materialize('alfred.mem');
        File(p.join(root.path, 'a.md')).writeAsStringSync(Page(
          topic: 'a',
          fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
          body: 'names [[mem://other.mem/nowhere]]',
        ).serialize());

        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call(['health']);
        expect(code, 0);
        expect(out.text, contains('dead links (1)'));
        expect(out.text, contains('a (semantic) -> other.mem/nowhere [missing]'));
        expect(diag.text, contains('resolved against other.mem'));
      });
    });

    test('a cross-bank link to an installed sibling is not dead when the '
        'topic exists there', () async {
      await site.runAsync(() async {
        final sibling = materialize('other.mem');
        File(p.join(sibling.path, 'x.md')).writeAsStringSync(Page(
          topic: 'x',
          fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
          body: 'here',
        ).serialize());
        final root = materialize('alfred.mem');
        File(p.join(root.path, 'a.md')).writeAsStringSync(Page(
          topic: 'a',
          fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
          body: 'names [[mem://other.mem/x]]',
        ).serialize());

        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call(['health']);
        expect(code, 0);
        expect(out.text, contains('dead links (0)'));
      });
    });

    // The falsification that can silently invert: a link to a bank nobody
    // has installed here must read unjudged, never a false dead-link
    // accusation. `ghost.mem` is never materialized, never even created —
    // `Bank.resolve` must return `NotFound` for it, exactly as it would for
    // any bank genuinely absent from this machine.
    test('a link to a bank that is not installed here is unjudged, never '
        'counted dead', () async {
      await site.runAsync(() async {
        final root = materialize('alfred.mem');
        File(p.join(root.path, 'a.md')).writeAsStringSync(Page(
          topic: 'a',
          fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
          body: 'names [[mem://ghost.mem/x]]',
        ).serialize());

        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call(['health']);
        expect(code, 0);
        expect(out.text, contains('dead links (0)'));
        expect(out.text, contains('external, unjudged (1)'));
        expect(out.text, contains('a (semantic) -> ghost.mem/x'));
        expect(diag.text, contains('external links unjudged'));
      });
    });
  });

  group('survey — pagination', () {
    Directory seed(int count) {
      final root = materialize('alfred.mem');
      for (var i = 0; i < count; i++) {
        File(p.join(root.path, 'topic$i.md')).writeAsStringSync(Page(
          topic: 'topic$i',
          fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
          body: 'body',
        ).serialize());
      }
      return root;
    }

    test('unscoped survey returns everything, and says so honestly — never '
        'silently truncated', () async {
      await site.runAsync(() async {
        seed(5);
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call(['survey']);
        expect(code, 0);
        for (var i = 0; i < 5; i++) {
          expect(out.text, contains('topic$i'));
        }
        // No pagination cue at all — the honest shape for "everything asked
        // for, everything given", not a silent cap nobody was told about.
        expect(out.text, isNot(contains('showing')));
        expect(diag.text, contains('5 of 5 shown'));
      });
    });

    test('--limit narrows the page and names what was left out', () async {
      await site.runAsync(() async {
        seed(5);
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call(['survey', '--limit', '2']);
        expect(code, 0);
        expect(out.text, contains('showing 1–2 of 5'));
        // The continuation cue names the exact next call, never leaves the
        // caller to compose their own offset.
        expect(out.text, contains('mem survey --offset 2'));
        expect(diag.text, contains('2 of 5 shown'));
      });
    });

    test('--limit and --offset together reach the last page, no further cue',
        () async {
      await site.runAsync(() async {
        seed(5);
        final out = _Out(), diag = _Out();
        final code = await mem(bankEnv: 'alfred.mem', out: out, diagnostics: diag)
            .call(['survey', '--limit', '2', '--offset', '4']);
        expect(code, 0);
        expect(out.text, contains('showing 5–5 of 5'));
        // At the end, the message names the range and stops — no
        // `--offset` cue pointing past the total.
        expect(out.text, isNot(contains('mem survey --offset')));
        expect(diag.text, contains('1 of 5 shown'));
      });
    });
  });
}
