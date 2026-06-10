import 'dart:io';

import 'package:test/test.dart';
import 'package:tx/tx.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('tx_test_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<int> commitCount(Directory repoDir) async {
    final r = await Process.run(
      'git',
      ['-C', repoDir.path, 'rev-list', '--count', 'HEAD'],
    );
    return int.parse((r.stdout as String).trim());
  }

  group('TxRepo — the content-blind contract', () {
    late TxRepo repo;

    setUp(() {
      repo = TxRepo(Directory('${tmp.path}/.tx/alfred'), 'alfred');
    });

    test('append → cat round-trips the exact bytes', () async {
      await repo.newSession();
      final line = '{"role":"user","text":"hi"}\n'.codeUnits;
      await repo.append(line);

      expect(repo.cat(), equals(line));
    });

    test('multiple appends accumulate in order', () async {
      await repo.newSession();
      final a = 'first\n'.codeUnits;
      final b = 'second\n'.codeUnits;
      await repo.append(a);
      await repo.append(b);

      expect(repo.cat(), equals([...a, ...b]));
    });

    test('one append == one commit (the write-ahead invariant)', () async {
      await repo.newSession(); // 1 commit
      await repo.append('a'.codeUnits);
      await repo.append('b'.codeUnits);
      await repo.append('c'.codeUnits);

      // new (1) + 3 appends = 4 commits.
      expect(await commitCount(repo.dir), equals(4));
    });

    test('an empty append still earns a commit', () async {
      await repo.newSession();
      await repo.append(const []);

      expect(await commitCount(repo.dir), equals(2));
      expect(repo.cat(), isEmpty);
    });

    test('content-blind: arbitrary non-UTF8 binary survives verbatim', () async {
      await repo.newSession();
      // Invalid UTF-8, embedded NUL, no trailing newline — tx must not care.
      final junk = [0xFF, 0xFE, 0x00, 0x01, 0x80, 0x7F];
      await repo.append(junk);

      expect(repo.cat(), equals(junk));
    });

    test('a fresh session starts empty', () async {
      await repo.newSession();
      expect(repo.cat(), isEmpty);
    });

    test('new session is an independent line (orphan, empty record)', () async {
      await repo.newSession();
      await repo.append('line-one\n'.codeUnits);
      await repo.newSession(); // fresh orphan

      expect(repo.cat(), isEmpty);
    });

    test('cat before any session errors', () {
      expect(repo.cat, throwsA(isA<TxNoSessionError>()));
    });

    test('append before any session errors', () {
      expect(
        () => repo.append('x'.codeUnits),
        throwsA(isA<TxNoSessionError>()),
      );
    });
  });

  group('TxRepo — structural ops (D2)', () {
    late TxRepo repo;

    setUp(() {
      repo = TxRepo(Directory('${tmp.path}/.tx/alfred'), 'alfred');
    });

    test('current is the session ref made by new', () async {
      final sid = await repo.newSession();
      expect(await repo.current(), equals(sid));
    });

    test('ls lists every session', () async {
      final a = await repo.newSession();
      final b = await repo.fork();
      expect(await repo.ls(), unorderedEquals([a, b]));
    });

    test('log lists one line per commit', () async {
      await repo.newSession(); // 1
      await repo.append('x'.codeUnits);
      await repo.append('y'.codeUnits);
      final lines = (await repo.log()).trim().split('\n');
      expect(lines, hasLength(3));
    });

    test('fork branches from current state and shares it', () async {
      await repo.newSession();
      await repo.append('shared\n'.codeUnits);
      await repo.fork();
      // The fork sees the parent's record at the fork point.
      expect(repo.cat(), equals('shared\n'.codeUnits));
    });

    test('fork becomes current; append diverges from parent', () async {
      final a = await repo.newSession();
      await repo.append('base\n'.codeUnits);
      final b = await repo.fork();
      expect(await repo.current(), equals(b));

      await repo.append('only-on-fork\n'.codeUnits);
      expect(repo.cat(), equals('base\nonly-on-fork\n'.codeUnits));

      // The parent line is untouched.
      await repo.switchTo(a);
      expect(repo.cat(), equals('base\n'.codeUnits));
    });

    test('switch resumes an existing session', () async {
      final a = await repo.newSession();
      await repo.append('in-a\n'.codeUnits);
      final b = await repo.fork();
      await repo.append('in-b\n'.codeUnits);

      await repo.switchTo(a);
      expect(await repo.current(), equals(a));
      expect(repo.cat(), equals('in-a\n'.codeUnits));

      await repo.switchTo(b);
      expect(repo.cat(), equals('in-a\nin-b\n'.codeUnits));
    });

    test('switch to a nonexistent session errors', () async {
      await repo.newSession();
      expect(() => repo.switchTo('nope'), throwsA(isA<TxNoSessionError>()));
    });

    test('rewind moves the ref back n commits; cat reflects it', () async {
      await repo.newSession();
      await repo.append('one\n'.codeUnits);
      await repo.append('two\n'.codeUnits);
      expect(repo.cat(), equals('one\ntwo\n'.codeUnits));

      await repo.rewind(1);
      expect(repo.cat(), equals('one\n'.codeUnits));

      await repo.rewind(1); // back to the empty `new` base
      expect(repo.cat(), isEmpty);
    });

    test('rewind past the base errors (floor is the new commit)', () async {
      await repo.newSession(); // total = 1
      await repo.append('x'.codeUnits); // total = 2
      expect(() => repo.rewind(2), throwsA(isA<TxGitError>()));
    });

    test('rewind with n < 1 errors', () async {
      await repo.newSession();
      expect(() => repo.rewind(0), throwsA(isA<TxGitError>()));
    });
  });

  group('resolveEntity', () {
    test('--agent flag wins', () {
      expect(resolveEntity('john', {'BENTOS_AGENT': 'alfred'}), equals('john'));
    });

    test('falls back to \$BENTOS_AGENT', () {
      expect(resolveEntity(null, {'BENTOS_AGENT': 'alfred'}), equals('alfred'));
    });

    test('no entity (operator never owns a log) errors', () {
      expect(() => resolveEntity(null, const {}), throwsA(isA<TxResolveError>()));
      expect(() => resolveEntity('', const {}), throwsA(isA<TxResolveError>()));
    });
  });

  group('resolvePlaceRoot — mirrors .mem', () {
    test('walks up to the governing place.yaml', () {
      File('${tmp.path}/place.yaml').writeAsStringSync('place: test\n');
      final deep = Directory('${tmp.path}/a/b/c')..createSync(recursive: true);

      expect(resolvePlaceRoot(deep).path, equals(Directory(tmp.path).absolute.path));
    });

    test('errors when no place.yaml is found upward', () {
      final orphan = Directory('${tmp.path}/no-place')..createSync();
      // tmp itself has no place.yaml; walk hits filesystem root without one
      // only if no ancestor has one. systemTemp ancestors don't, so this holds.
      expect(() => resolvePlaceRoot(orphan), throwsA(isA<TxResolveError>()));
    });

    test('resolveRepoDir lands at <place>/.tx/<entity>', () {
      File('${tmp.path}/place.yaml').writeAsStringSync('place: test\n');
      final start = Directory('${tmp.path}/work')..createSync();

      final repoDir = resolveRepoDir('iris', start);
      expect(
        repoDir.path,
        equals('${Directory(tmp.path).absolute.path}/.tx/iris'),
      );
    });
  });
}
