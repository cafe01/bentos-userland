import 'dart:async';
import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:bentos_userland/src/mem/attention.dart';
import 'package:bentos_userland/src/mem/bank.dart' show Bank, Found;
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

  /// A page the bank genuinely holds — landed as an act and then brought into
  /// the tree, rather than dropped into the worktree by hand.
  ///
  /// The difference is not fussiness. A hand-planted file is untracked
  /// forever, so every later write leaves the tree behind it, and a verb under
  /// test then reports a stale tree instead of answering for its own grammar.
  /// These fixtures passed only while a stale tree exited zero.
  Future<void> plant(String bankName, String topic) async {
    final bank =
        (Bank.resolve(bankName, vantage: site.root.path) as Found).bank;
    await bank.land(
      'page',
      (draft) => draft.write(Page(
        topic: topic,
        fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
        body: 'body of $topic',
      )),
      actor: Actor('tester', email: 'tester@test.local'),
    );
    bank.advance();
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
      'refocus': 'refocus [<topic>...]',
      'tag': 'tag [<topic>...]',
      'gist': 'gist [<topic>...]',
      'forget': 'forget <topic>...',
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
      await plant('alfred.mem', 'a');
      final cli = mem();
      final code =
          await cli.call(['tag', '-b', 'alfred.mem', ...signed, '--add', 'x', '--cool']);
      expect(code, 0);
    });

    test('tag with a topic reaches exactly that page', () async {
      materialize('alfred.mem');
      await plant('alfred.mem', 'a');
      final cli = mem();
      final code = await cli.call(['tag', 'a', '-b', 'alfred.mem', ...signed, '--add', 'x']);
      expect(code, 0);
    });

    test('a second topic is written, and an absent one is named — never '
        'silently dropped', () async {
      materialize('alfred.mem');
      await plant('alfred.mem', 'alice');
      await plant('alfred.mem', 'carol');
      final out = _Out();
      final diag = _Out();
      final cli = Mem(
        vantage: site.root.path,
        out: out,
        diagnostics: diag,
        environment: const {},
      );
      // The shape found in use: `mem tag --add foo alice bob` used to tag
      // `alice` and let `bob` vanish at exit 0. Now both slots are the
      // caller's, and the one with no page behind it is reported.
      final code = await cli.call([
        'tag', 'alice', 'carol', 'bob',
        '-b', 'alfred.mem', ...signed, '--add', 'foo',
      ]);
      expect(code, 0);
      expect(diag.text, contains('alice'));
      expect(diag.text, contains('carol'));
      expect(diag.text, contains('no page at bob'));
      final alice = Page.parse(
        'alice',
        File(p.join(site.root.path, 'alfred.mem', 'alice.md')).readAsStringSync(),
      );
      final carol = Page.parse(
        'carol',
        File(p.join(site.root.path, 'alfred.mem', 'carol.md')).readAsStringSync(),
      );
      expect(alice.fields.tags, contains('foo'));
      expect(carol.fields.tags, contains('foo'));
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

  group('exact-one verbs — remember', () {
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
  });

  group('forget — variadic, min one, checked before it lands', () {
    // Landed as acts, not planted by hand — a hand-written file is
    // untracked, and forget is a write: it lands an act, which refuses
    // outright against a tree already carrying uncommitted work.
    Future<void> seed(String bank, List<String> topics) async {
      materialize(bank);
      for (final topic in topics) {
        await plant(bank, topic);
      }
    }

    test('zero topics is refused as usage — a selector must never delete',
        () async {
      materialize('alfred.mem');
      final diag = _Out();
      final cli = Mem(
          vantage: site.root.path,
          out: _Out(),
          diagnostics: diag,
          environment: const {});
      final code = await cli.call(['forget', '-b', 'alfred.mem', ...signed]);
      expect(code, 2);
      expect(diag.text, contains('<topic> is required'));
    });

    test('many topics are removed in one call', () async {
      await seed('alfred.mem', ['a', 'b', 'c']);
      final diag = _Out();
      final cli = Mem(
          vantage: site.root.path,
          out: _Out(),
          diagnostics: diag,
          environment: const {});
      final code =
          await cli.call(['forget', 'a', 'b', 'c', '-b', 'alfred.mem', ...signed]);
      expect(code, 0);
      expect(diag.text, contains('written a, b, c'));

      final out = _Out();
      final recallDiag = _Out();
      await Mem(
              vantage: site.root.path,
              out: out,
              diagnostics: recallDiag,
              environment: const {})
          .call(['recall', 'a', 'b', 'c', '-b', 'alfred.mem']);
      expect(recallDiag.text, contains('no page at a in alfred.mem'));
    });

    // The defect this closes: before this change, forgetting a name that
    // was never a page reported `written ghost` at exit 0 — [Draft.remove]
    // no-ops on a missing file, so the CLI told the caller a deletion
    // happened when nothing on disk moved. This is the reproduction: it
    // would have read `code == 0` and `diag.text` carrying `written ghost`
    // against the code before this slice.
    test('a nonexistent topic is refused, never reported written', () async {
      materialize('alfred.mem');
      final diag = _Out();
      final cli = Mem(
          vantage: site.root.path,
          out: _Out(),
          diagnostics: diag,
          environment: const {});
      final code =
          await cli.call(['forget', 'ghost', '-b', 'alfred.mem', ...signed]);
      expect(code, 1);
      expect(diag.text, contains('no page at ghost in alfred.mem'));
      expect(diag.text, isNot(contains('written')));
    });

    test('a batch with one typo lands the real topics and names the typo '
        'in full, exit 0 — a partial miss, not a failed call', () async {
      await seed('alfred.mem', ['a', 'b']);
      final diag = _Out();
      final cli = Mem(
          vantage: site.root.path,
          out: _Out(),
          diagnostics: diag,
          environment: const {});
      final code = await cli
          .call(['forget', 'a', 'ghost', 'b', '-b', 'alfred.mem', ...signed]);
      expect(code, 0);
      expect(diag.text, contains('written a, b'));
      expect(diag.text, contains('no page at ghost in alfred.mem'));

      final out = _Out();
      final recallDiag = _Out();
      await Mem(
              vantage: site.root.path,
              out: out,
              diagnostics: recallDiag,
              environment: const {})
          .call(['recall', 'a', 'b', '-b', 'alfred.mem']);
      expect(recallDiag.text, contains('no page at a in alfred.mem'));
    });

    test('a repeated topic is deduplicated, not landed twice', () async {
      await seed('alfred.mem', ['a']);
      final diag = _Out();
      final cli = Mem(
          vantage: site.root.path,
          out: _Out(),
          diagnostics: diag,
          environment: const {});
      final code =
          await cli.call(['forget', 'a', 'a', '-b', 'alfred.mem', ...signed]);
      expect(code, 0);
      expect(diag.text, contains('written a'));
      expect(diag.text, isNot(contains('written a, a')));
    });
  });

  group('unknown-option — the pool is this call\'s grammar, not every verb\'s',
      () {
    Future<String> refuse(List<String> args) async {
      final diag = _Out();
      final cli = Mem(
          vantage: site.root.path,
          out: _Out(),
          diagnostics: diag,
          environment: const {});
      expect(await cli.call(args), 2);
      return diag.text;
    }

    test('a live flag of another verb is located, never suggested back',
        () async {
      // Observed verbatim: `mem survey --limit 200 --shape` answered
      // "no option --shape. Did you mean --shape?" — walk's real flag,
      // ranked against a survey call.
      final text = await refuse(['survey', '--limit', '200', '--shape']);
      expect(text, contains('no option --shape on survey'));
      expect(text, contains("--shape is walk's flag"));
      expect(text, isNot(contains('Did you mean --shape?')));
    });

    test('a near miss inside the verb\'s own grammar still resolves', () async {
      final text = await refuse(['walk', 'root', '--shapee']);
      expect(text, contains('Did you mean --shape?'));
    });

    test('nothing within two edits answers with the bare fact', () async {
      // `mem --version` answered "Did you mean --attention?" — refocus's
      // flag, at a distance no threshold was checking.
      final text = await refuse(['--version']);
      expect(text, contains('no option --version.'));
      expect(text, isNot(contains('Did you mean')));
    });

    test('a retired name still answers exactly, before any search', () async {
      final text = await refuse(['walk', 'root', '--dry-run']);
      expect(text, contains('no option --dry-run. Did you mean --shape?'));
    });

    test('the verb is the parser\'s, never argv\'s first command-shaped word',
        () async {
      // `-b survey` names a bank; the verb is `recall`, and the refusal must
      // report recall's grammar rather than survey's.
      final text = await refuse(['-b', 'survey', 'recall', 'a', '--offset', '2']);
      expect(text, contains('no option --offset on recall'));
      expect(text, contains("--offset is survey's flag"));
    });
  });
}
