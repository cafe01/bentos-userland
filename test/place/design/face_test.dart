// Face — the `place` coreutil: verbs over the components, the vantage captured
// once, diagnostics on the value, exit codes decided, vocabulary the place's.
import 'dart:io';

import 'package:bentos_userland/src/entity/contract/contract.dart' hide Landed, Gated;
import 'package:bentos_userland/src/place/contract/contract.dart';
import 'package:test/test.dart';

import 'design_helpers.dart';
import 'fake_entity.dart';

final class Out implements Sink<String> {
  final StringBuffer b = StringBuffer();
  @override
  void add(String data) => b.write(data);
  @override
  void close() {}
  @override
  String toString() => b.toString();
}

void main() {
  late FakeGate gate;
  setUp(() => gate = FakeGate());

  Future<(int, String, String)> run(List<String> argv, {String vantage = '/home/john/hq', Actor? actor}) async {
    final out = Out();
    final err = Out();
    final code = await PlaceRunner(vantage: vantage, actor: actor, out: out, err: err).run(argv);
    return (code, out.toString(), err.toString());
  }

  /// No line of output names the substrate.
  final substrate = RegExp(r'\b(repository|repo|branch|commit|remote|checkout|worktree|submodule|gitlink|sha)\b', caseSensitive: false);

  group('exit codes', () {
    test('0 for did-it, including a resolution that found nothing and a survey of an empty place', () async {
      await runPlace(gate, (fs) async {
        await genesis('/home/john/hq');
        expect((await run(['ls'])).$1, 0);
        expect((await run(['resolve', 'nothing'])).$1, 0);
      });
    });

    test('64 for a writing verb with nobody stated as the actor, before anything runs', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        final before = ownCopy(gate, place).actCalls.length;
        expect((await run(['reside', 'ada', '--kind', 'being'])).$1, 64);
        expect(ownCopy(gate, place).actCalls.length, before);
        expect((await run(['reside', 'ada', '--kind', 'being'], actor: tester)).$1, 0);
      });
    });

    test('2 for an invalid call, with the offending argument named', () async {
      await runPlace(gate, (fs) async {
        await genesis('/home/john/hq');
        final (code, _, err) = await run(['standing']);
        expect(code, 2, reason: 'there is no unscoped form');
        expect(err, contains('scope'));
        expect((await run(['hold', 'deck'], actor: tester)).$1, 2);
      });
    });

    test('1 for a decided refusal: a source unreachable, a held instance asked to move, a name resolving nowhere for a verb that needs one', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        await installThing(gate, place, 'aviacao.chat', instances: const [Seed('c1')]);
        copyOf(gate, place, 'aviacao.chat').unreachable.add('hub');
        final (code, out, _) = await run(['sync', '--thing', 'aviacao.chat']);
        expect(code, 1);
        expect(out, contains('hub'), reason: 'names the source');
        expect((await run(['path', 'nothing'])).$1, 1);
      });
    });
  });

  group('verbs', () {
    test('ls draws the desk: things with instances by title, present and held marked, rooms, loose', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq', name: 'HQ');
        await installThing(gate, place, 'aviacao.chat', instances: const [Seed('c1', title: 'AWS cutover'), Seed('c2', title: 'Kickoff')]);
        await Presence(place).present('aviacao.chat', 'c1');
        await place.arrangement.hold('aviacao.chat', 'c2', pt(0), actor: tester);
        await genesis('/home/john/hq/aviacao');
        File('/home/john/hq/photo.jpg').writeAsStringSync('');
        final (code, out, _) = await run(['ls']);
        expect(code, 0);
        expect(out, contains('AWS cutover'));
        expect(out, contains('Kickoff'));
        expect(out, isNot(contains('c1')), reason: 'the title, never the handle');
        expect(out, contains('aviacao'));
        expect(out, contains('photo.jpg'));
        expect(out, isNot(matches(substrate)));
      });
    });

    test('standing prints one counter line per pair, every line with its age; unknown says so', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        await installThing(gate, place, 'aviacao.chat', instances: const [Seed('c1', title: 'AWS cutover'), Seed('c2', title: 'Kickoff')]);
        final copy = copyOf(gate, place, 'aviacao.chat');
        copy.standings['hub'] = {'c1': Standing.known(relation: Relation.behind, behind: 2, ahead: 0, contacted: DateTime.now().subtract(const Duration(minutes: 3)))};
        final (code, out, _) = await run(['standing', '--thing', 'aviacao.chat']);
        expect(code, 0);
        final lines = out.trim().split('\n').where((l) => l.contains('hub')).toList();
        expect(lines, hasLength(2));
        expect(lines[0], allOf(contains('AWS cutover'), contains('behind'), contains('2'), matches(RegExp(r'\d+\s*m|min|ago'))));
        expect(lines[1], allOf(contains('Kickoff'), contains('unknown')));
        expect(out, isNot(matches(substrate)));
      });
    });

    test('a held instance is printed as held with the distance past the pin, never as behind', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        await installThing(gate, place, 'deck', instances: const [Seed('v2', title: 'v2')]);
        await place.arrangement.hold('deck', 'v2', pt(1), actor: tester);
        final copy = copyOf(gate, place, 'deck');
        copy.pastPoint['hub'] = {'v2': {pt(1): 3}};
        copy.contacted['hub'] = DateTime.now();
        final (_, out, _) = await run(['standing', '--thing', 'deck']);
        final line = out.trim().split('\n').firstWhere((l) => l.contains('v2'));
        expect(line, contains('held'));
        expect(line, contains('3'));
        expect(line, isNot(matches(RegExp(r'^\s*\S+\s+\S+\s+behind'))), reason: 'held · 3 behind hub, not behind');
      });
    });

    test('sync prints every pair, what moved and what could not and why, and exits 1 if any pair refused', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        await installThing(gate, place, 'aviacao.chat', instances: const [Seed('c1', title: 'AWS cutover'), Seed('c2', title: 'Kickoff')]);
        final copy = copyOf(gate, place, 'aviacao.chat');
        copy.sources.add(const Source(name: 'mirror', address: 'mirror:/a', roles: {Role.follow}, cadence: ByHand()));
        copy.unreachable.add('hub');
        copy.moveAnswers[('c1', 'mirror')] = const Carried(instance: 'c1', source: 'mirror', direction: Direction.bringCurrent, landings: 2);
        final (code, out, _) = await run(['sync', '--thing', 'aviacao.chat']);
        expect(code, 1);
        expect(out.trim().split('\n').where((l) => l.contains('hub') || l.contains('mirror')), hasLength(4), reason: 'every pair is printed');
        expect(out, contains('2'), reason: 'landings carried');
      });
    });

    test('install asks only where: the address, and the vantage as the place', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        gate.remotes['hub:/things/aviacao.chat'] = FakeRemote(manifestOf('aviacao.chat'));
        final (code, _, _) = await run(['install', 'hub:/things/aviacao.chat'], actor: tester);
        expect(code, 0);
        expect(place.arrangement.things.map((t) => t.name), ['aviacao.chat']);
      });
    });

    test('the vantage is read once and passed down: a verb from inside a stood line resolves the same place', () async {
      await runPlace(gate, (fs) async {
        final ws = await genesis('/home/john/ws');
        final hq = await genesis('/home/john/ws/hq');
        await installThing(gate, ws, 'rate-table');
        final alt = await hq.stand(await hq.fork('alt', actor: tester));
        final (code, out, _) = await run(['resolve', 'rate-table'], vantage: alt.root.path);
        expect(code, 0);
        expect(out, contains(ws.root.path));
      });
    });

    test('vocabulary is the place\'s: no verb, flag or line of output names the substrate', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        await installThing(gate, place, 'aviacao.chat', instances: const [Seed('c1')]);
        for (final argv in [['where'], ['info'], ['tree'], ['who'], ['ls'], ['lines'], ['line'], ['resolve', 'aviacao.chat'], ['path', 'aviacao.chat', 'c1'], ['standing', '--place'], ['plot', 'mem']]) {
          final (code, out, err) = await run(argv);
          expect(code, 0, reason: argv.join(' '));
          expect(out + err, isNot(matches(substrate)), reason: argv.join(' '));
        }
        final (code, _, err) = await run(['pin', 'x']);
        expect(code, 2, reason: 'a retired verb is not a verb');
        expect(err, isNot(matches(substrate)));
      });
    });

    test('a JSON form of the same value on request', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq', name: 'HQ');
        await installThing(gate, place, 'aviacao.chat', instances: const [Seed('c1', title: 'AWS cutover')]);
        final (code, out, _) = await run(['ls', '--json']);
        expect(code, 0);
        expect(out, contains('"AWS cutover"'));
        expect(out, contains('"HQ"'));
      });
    });
  });
}
