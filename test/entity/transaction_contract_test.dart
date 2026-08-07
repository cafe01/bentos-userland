import 'package:bentos_userland/entity.dart';
// The transaction triple is the shim's input and `emit`'s argument, and
// neither is published yet — it is imported where it lives until the slice
// that has a caller decides what the surface says.
import 'package:bentos_userland/src/entity/transaction.dart';
import 'package:test/test.dart';

/// **The transaction triple.** What the reference-transaction hook reads off
/// stdin, one line per ref moving — `<old> <new> <ref>`.
///
/// It is its own type and not `RefUpdate`, which is the *result* of a
/// compare-and-swap. Two different facts under one name is the defect this
/// design closes elsewhere, and it would be reintroduced here for the sake of
/// three fields that happen to rhyme.
void main() {
  group('parsing one stdin line', () {
    test('the three fields are old, new and the ref', () {
      final u = TransactionRefUpdate.parse(
        '1111111111111111111111111111111111111111 '
        '2222222222222222222222222222222222222222 '
        'refs/heads/demo',
      );
      expect(u.old.sha, '1111111111111111111111111111111111111111');
      expect(u.commit.sha, '2222222222222222222222222222222222222222');
      expect(u.ref, 'refs/heads/demo');
    });

    test('a birth is a zero old value', () {
      final u = TransactionRefUpdate.parse(
        '${Commit.zero.sha} '
        '2222222222222222222222222222222222222222 '
        'refs/heads/demo',
      );
      expect(u.old.isZero, isTrue);
      expect(u.commit.isZero, isFalse);
    });

    test('a deletion is a zero new value', () {
      final u = TransactionRefUpdate.parse(
        '1111111111111111111111111111111111111111 '
        '${Commit.zero.sha} '
        'refs/heads/demo',
      );
      expect(u.old.isZero, isFalse);
      expect(u.commit.isZero, isTrue);
    });

    // Git writes single spaces, but the line arrives through a shell that has
    // touched nothing — assuming one separator is assuming about a transport
    // rather than reading it.
    test('any run of whitespace separates, and the line is trimmed', () {
      final u = TransactionRefUpdate.parse(
        '  1111111111111111111111111111111111111111\t'
        '2222222222222222222222222222222222222222   '
        'refs/heads/demo\n',
      );
      expect(u.old.sha, '1111111111111111111111111111111111111111');
      expect(u.ref, 'refs/heads/demo');
    });

    test('a ref name keeps its slashes and dots', () {
      final u = TransactionRefUpdate.parse(
        '${Commit.zero.sha} ${Commit.zero.sha} refs/heads/feature/x.y',
      );
      expect(u.ref, 'refs/heads/feature/x.y');
    });
  });

  // The shim never hands this a line it did not read verbatim from Git, so a
  // malformed line is a broken contract with the substrate and not a user
  // typo — it raises rather than degrading into a triple with an empty field,
  // which would be dispatched against and match something.
  group('a line that is not a triple raises', () {
    test('two fields', () {
      expect(
        () => TransactionRefUpdate.parse('${Commit.zero.sha} refs/heads/demo'),
        throwsFormatException,
      );
    });

    test('four fields', () {
      expect(
        () => TransactionRefUpdate.parse(
          '${Commit.zero.sha} ${Commit.zero.sha} refs/heads/demo extra',
        ),
        throwsFormatException,
      );
    });

    test('an empty line', () {
      expect(() => TransactionRefUpdate.parse(''), throwsFormatException);
      expect(() => TransactionRefUpdate.parse('   \n'), throwsFormatException);
    });
  });
}
