/// The one claim that guards the seam between the two chairs.
///
/// `session_contract_test.dart` is tagged `owed` while no construction exists,
/// so the fast gate stays green in the meantime. The hazard that buys is
/// green-by-absence: a construction lands, the tag stays, and the whole contract
/// suite quietly stops running in the gate everybody watches.
///
/// This claim is structural and needs no discipline to hold: the moment the
/// construction file exists, the plug point must not be tagged out.
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('a delivered construction is a contract suite that actually runs', () {
    final construction = File('lib/src/llm/session/construction.dart');
    final plugPoint = File('test/llm/session/session_contract_test.dart');

    expect(plugPoint.existsSync(), isTrue,
        reason: 'the plug point is the suite reach itself; it is not deleted');

    final taggedOut = plugPoint.readAsStringSync().contains("@Tags(['owed'])");

    if (construction.existsSync()) {
      expect(
        taggedOut,
        isFalse,
        reason:
            'lib/src/llm/session/construction.dart exists, so llm session has '
            'an implementation — but the contract suite is still tagged `owed` '
            'and therefore skipped by the gate. Remove the @Tags line from '
            'test/llm/session/session_contract_test.dart.',
      );
    } else {
      expect(
        taggedOut,
        isTrue,
        reason:
            'there is no construction yet, so the plug point must stay tagged '
            '`owed` — otherwise the gate is red for a chair that has not been '
            'asked to deliver, and a red nobody owns gets deleted.',
      );
    }
  });
}
