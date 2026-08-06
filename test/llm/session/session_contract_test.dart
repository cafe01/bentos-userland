/// The plug point: two lines, and the contract suite judges the delivery.
///
/// It is red today, on purpose and with instructions. The construction chair
/// replaces the body of `main` with the call below; no claim in
/// `contract_suite.dart` is touched, then or ever.
///
/// Tagged `owed` so the suite that runs fifty times a day stays green while the
/// chair that owes the implementation has not delivered — a red with no owner
/// present gets deleted, not fixed. **Dropping this tag is part of plugging in**,
/// and `plug_point_guard_test.dart` is what notices if it is not.
@Tags(['owed'])
library;

import 'package:test/test.dart';

import 'contract_suite.dart';

void main() {
  test('a construction is plugged into the contract suite', () {
    // Named so this file will not compile once the symbol moves or is renamed:
    // a plug point that silently stops reaching the suite is worse than a red.
    final suite = runSessionContract;
    expect(suite, isNotNull);

    fail(
      'llm session: no SessionConstruction on this delivery.\n'
      '\n'
      'The construction chair writes '
      'lib/src/llm/session/construction.dart, exposing:\n'
      '\n'
      '    final SessionConstruction sessionConstruction = ...;\n'
      '\n'
      'and then this whole main() becomes exactly:\n'
      '\n'
      "    import 'package:bentos_userland/src/llm/session/construction.dart';\n"
      '    void main() => runSessionContract(sessionConstruction);\n'
      '\n'
      'The suite itself is not edited — not to plug it in, and not to make it '
      'pass.',
    );
  });
}
