import 'dart:collection';

import 'package:bentos_userland/src/chat/handle.dart';
import 'package:bentos_userland/src/chat/model.dart';
import 'package:bentos_userland/src/chat_client/transcript.dart';
import 'package:test/test.dart';

Message _msg(String id, [String body = 'hi']) => Message(
  id: id,
  author: const Handle('cafe', ''),
  spoken: DateTime(2026, 1, 1),
  body: body,
);

/// A witness for cost, not correctness: counts every element index actually
/// read off the backing store, so a claim about *how much* a scan touched is
/// falsifiable without a stopwatch. Building history through [Transcript]
/// never touches `[]` — [ListBase]'s `add` writes through `length`/`[]=` —
/// so a fresh count after setup measures only the read under test.
final class _CountingLines extends ListBase<TranscriptLine> {
  _CountingLines(this._inner);

  final List<TranscriptLine> _inner;
  int reads = 0;

  @override
  int get length => _inner.length;

  @override
  set length(int newLength) => _inner.length = newLength;

  @override
  TranscriptLine operator [](int index) {
    reads++;
    return _inner[index];
  }

  @override
  void operator []=(int index, TranscriptLine value) => _inner[index] = value;

  // ListBase's default `add` grows via `length=`, which pads with `null` —
  // fine for a nullable element type, fatal for this non-nullable one.
  // Delegate straight to the real list instead.
  @override
  void add(TranscriptLine element) => _inner.add(element);
}

void main() {
  group('Transcript', () {
    test('a fresh transcript with no mark counts unread history', () {
      final t = Transcript();
      t.append(SpokenLine(_msg('a')));
      t.append(SpokenLine(_msg('b')));

      expect(t.unreadCount, 2);
    });

    test('markRead on an empty transcript stays caught up as lines arrive', () {
      final t = Transcript()..markRead();

      expect(t.unreadCount, 0);
      expect(t.readMark, isNull);

      t.append(SpokenLine(_msg('a')));
      expect(t.unreadCount, 1);
    });

    test('markRead anchors on the last message id, not a line index', () {
      final t = Transcript();
      t.append(SpokenLine(_msg('a')));
      t.append(SpokenLine(_msg('b')));
      t.markRead();

      expect(t.readMark, 'b');
      expect(t.unreadCount, 0);

      t.append(SpokenLine(_msg('c')));
      expect(t.unreadCount, 1);
    });

    test('a topic line is not a message and never anchors the mark', () {
      final t = Transcript();
      t.append(SpokenLine(_msg('a')));
      t.append(
        TopicLine('new topic', const Handle('cafe', ''), DateTime(2026, 1, 1)),
      );
      t.markRead();

      expect(t.readMark, 'a');
    });

    test('lines is a live view over the backing store, never a copy', () {
      final t = Transcript();
      t.append(SpokenLine(_msg('a')));
      final view = t.lines;
      expect(view, hasLength(1));

      t.append(SpokenLine(_msg('b')));
      // A copy taken when `lines` was read would freeze at length 1; a
      // genuine view reflects growth in the backing store with no second
      // read of it.
      expect(view, hasLength(2));
    });

    test(
      'reading lines touches nothing — a render pays only for the window it slices',
      () {
        final backing = _CountingLines(<TranscriptLine>[]);
        final t = Transcript(backing: backing);
        for (var i = 0; i < 5000; i++) {
          t.append(SpokenLine(_msg('m$i')));
        }

        backing.reads = 0;
        final view = t.lines;

        expect(backing.reads, 0);
        expect(view, hasLength(5000));
      },
    );

    test(
      'unreadTail is bounded by the unread tail, never by total history',
      () {
        final backing = _CountingLines(<TranscriptLine>[]);
        final t = Transcript(backing: backing);
        for (var i = 0; i < 20000; i++) {
          t.append(SpokenLine(_msg('m$i')));
        }
        t.markRead();
        t.append(SpokenLine(_msg('new-1')));
        t.append(SpokenLine(_msg('new-2')));

        backing.reads = 0;
        final tail = t.unreadTail();

        expect(tail.count, 2);
        expect(tail.boundaryIndex, 20000);
        // The cost tracks the 2 unread lines, not the 20002 held — a room
        // with real scrollback must not pay for it on a read that only needs
        // the tail.
        expect(backing.reads, lessThan(10));
      },
    );

    test('a SystemLine defaults to warning, matching every existing caller', () {
      final line = SystemLine('refused: not a member', DateTime(2026));
      expect(line.kind, SystemLineKind.warning);
    });

    test('a SystemLine can be authored as a notice explicitly', () {
      final line = SystemLine(
        'you joined bentos.chat:design',
        DateTime(2026),
        kind: SystemLineKind.notice,
      );
      expect(line.kind, SystemLineKind.notice);
    });

    test(
      'a caller needing both count and boundary pays for one pass, not two',
      () {
        final backing = _CountingLines(<TranscriptLine>[]);
        final t = Transcript(backing: backing);
        for (var i = 0; i < 20000; i++) {
          t.append(SpokenLine(_msg('m$i')));
        }
        t.markRead();
        t.append(SpokenLine(_msg('new-1')));

        backing.reads = 0;
        final tail = t.unreadTail();
        final onePassReads = backing.reads;

        backing.reads = 0;
        // ignore: unused_local_variable
        final count = t.unreadCount;
        // ignore: unused_local_variable
        final boundary = t.unreadBoundaryIndex;
        final twoGetterReads = backing.reads;

        expect(tail.boundaryIndex, 20000);
        // Calling the two convenience getters separately re-walks the tail
        // twice — exactly the waste `unreadTail` exists so a caller need not
        // pay for.
        expect(twoGetterReads, greaterThan(onePassReads));
      },
    );
  });
}
