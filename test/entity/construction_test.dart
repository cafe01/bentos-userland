import 'package:test/test.dart';

/// **Tier C — what only the real substrate can answer.**
///
/// Every test here is skipped, naming construction as the chair that unskips
/// it. They are written now, at design time, for one reason: these are the
/// questions a fake **cannot** be asked, and a suite that only asks the
/// answerable ones drifts into proving the double.
///
/// A green fake proves the model. Only these prove the machine.
const _owed = 'construction: real git, real repositories';

void main() {
  group('the port against the real substrate', () {
    test('a bare repository is created, and it is bare', () {}, skip: _owed);

    test('the plumbing quartet writes a commit reachable by the real git', () {},
        skip: _owed);

    test('update-ref with a stale expectation is refused by git itself', () {},
        skip: _owed);

    test('an empty expectation refuses a ref that already exists', () {},
        skip: _owed);

    test('a worktree shares the object store with the entity', () {}, skip: _owed);
  });

  group('the shim, mounted for real', () {
    test('git runs the hook out of the common dir, even from a worktree', () {},
        skip: _owed);

    test('a refusing listener aborts the real ref update, and the tip is unmoved',
        () {}, skip: _owed);

    test('the action noun is read back off a real commit object', () {},
        skip: _owed);

    test('a landing wakes a subscriber that outlives the git process', () {},
        skip: _owed);
  });

  group('federation — the axis no other gate varies', () {
    // Four gates of the PoC varied the state inside one machine and all
    // passed; the fifth varied the machine, and was the only one that could
    // expose a locality dependency. It found one on its first run.
    test('a clone arms differently and reacts to a pushed act', () {}, skip: _owed);

    test('the receiving side runs its own hook on push', () {}, skip: _owed);

    test('a site that only reacts holds no worktree and still reads state', () {},
        skip: _owed);
  });

  group('acceptance', () {
    // The lab's `bash test/gates.sh` walks the whole vocabulary of
    // `bentos.llm` on raw Git — five gates, twenty-three assertions, no API
    // key. Construction promotes it: the same gates, driven through the
    // `entity` coreutil instead of hand-spelled shell, is the acceptance proof
    // that the primitive absorbed the PoC without losing a property.
    //
    // Source: `lab/entity/test/gates.sh` · promotion list: `lab/entity/PROMOTION.md`
    test('the lab gates pass driven through the entity coreutil', () {},
        skip: 'construction: promote lab/entity/test/gates.sh');
  });
}
