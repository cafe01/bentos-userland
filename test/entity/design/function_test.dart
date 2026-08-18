import 'package:bentos_userland/src/entity/contract/contract.dart';
import 'package:test/test.dart';

import 'ground.dart';

/// R2.8.1 — a caller names a verb and an instance and never learns the layout.
void main() {
  tearDown(disposeGrounds);

  test('a declared function runs against the instance, with its state as the ground', () async {
    final shipping = Manifest(
      name: 'shipping.chat',
      kind: 'chat',
      instanceName: thing.instanceName,
      rhythm: thing.rhythm,
      functions: const {'count': 'sh -c "ls messages | wc -l"'},
    );
    final g = await Ground.stand(manifest: shipping);
    final s1 = await g.a.instance('s1').born(by: alice);
    await landed(s1, by: alice, path: 'messages/1.txt');
    await landed(s1, by: alice, path: 'messages/2.txt');
    final r = await s1.run('count');
    expect(r.code, 0);
    expect(r.out.trim(), '2');
  });

  test('a verb the manifest does not name is refused as such, never as a shell error', () async {
    final g = await Ground.stand();
    final s1 = await g.a.instance('s1').born(by: alice);
    await expectLater(
      s1.run('nope'),
      throwsA(isA<FunctionNotDeclared>()
          .having((e) => e.verb, 'verb', 'nope')
          .having((e) => e.entity, 'entity', thing.name)),
    );
  });
}
