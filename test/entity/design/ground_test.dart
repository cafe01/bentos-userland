import 'package:bentos_userland/src/entity/contract/contract.dart';
import 'package:test/test.dart';

import 'ground.dart';

/// The suite's own two rules, proven on the ground before anything else.
void main() {
  late Ground g;
  setUp(() async => g = await Ground.stand());
  tearDown(disposeGrounds);

  test('no source in the suite is anything but a path on this disk', () {
    for (final copy in [g.a, g.b]) {
      for (final source in copy.sources) {
        expect(source.address, startsWith('/'),
            reason: 'the suite never reaches the network');
        expect(source.address, isNot(contains('://')));
      }
    }
  });

  test('the type forbids an undated standing and a dated unknown', () {
    const unknown = Standing.unknown();
    expect(unknown.contacted, isNull);
    expect(unknown.relation, Relation.unknown);
    final known = Standing.known(
      relation: Relation.behind,
      behind: 2,
      ahead: 0,
      contacted: DateTime.now(),
    );
    expect(known.contacted, isNotNull);
    expectStanding(known, Relation.behind, behind: 2);
  });

  test('both copies stand, hold the hub as source, and agree on the name', () {
    expect(g.a.name, thing.name);
    expect(g.b.name, thing.name);
    expect(g.a.sources.map((s) => s.name), contains(hub));
    expect(g.b.sources.map((s) => s.name), contains(hub));
    expect(g.b.plot.path, isNot(g.b.directory.path));
  });
}
