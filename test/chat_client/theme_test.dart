/// The role vocabulary, asserted with no terminal and no framework — which
/// is the whole reason it is core and not adapter.
library;

import 'package:bentos_userland/src/chat_client/activity.dart';
import 'package:bentos_userland/src/chat_client/screen_model.dart';
import 'package:bentos_userland/src/chat_client/theme.dart';
import 'package:bentos_userland/src/chat_client/transcript.dart';
import 'package:bentos_userland/src/chat/handle.dart';
import 'package:bentos_userland/src/chat/model.dart';
import 'package:test/test.dart';

void main() {
  group('a line carries its role', () {
    final at = DateTime.utc(2026, 8, 12, 14, 2);

    test('speech is body', () {
      expect(roleOfLine(SpokenLine(_message(at))), Role.body);
    });

    test('a topic change is secondary', () {
      expect(
        roleOfLine(
          TopicLine('the factory floor', Handle('alfred', 'bentos.life'), at),
        ),
        Role.secondary,
      );
    });

    test('a notice is secondary and a warning is a failure', () {
      expect(
        roleOfLine(SystemLine('you joined', at, kind: SystemLineKind.notice)),
        Role.secondary,
      );
      expect(
        roleOfLine(SystemLine('unknown command: /frobnicate', at)),
        Role.failure,
      );
    });

    test('a notice and a warning do not read alike', () {
      final notice = roleOfLine(
        SystemLine('you joined', at, kind: SystemLineKind.notice),
      );
      final warning = roleOfLine(
        SystemLine('refused: not a member', at, kind: SystemLineKind.warning),
      );
      expect(notice, isNot(warning));
    });
  });

  group('a tab carries its role', () {
    test('a mention is the loudest role, current or not', () {
      expect(
        roleOfTab(_tab(level: ActivityLevel.mention, isCurrent: false)),
        Role.highlight,
      );
      expect(
        roleOfTab(_tab(level: ActivityLevel.mention, isCurrent: true)),
        Role.highlight,
      );
    });

    test('the current room is body and any other is secondary', () {
      expect(
        roleOfTab(_tab(level: ActivityLevel.none, isCurrent: true)),
        Role.body,
      );
      expect(
        roleOfTab(_tab(level: ActivityLevel.speech, isCurrent: false)),
        Role.secondary,
      );
    });
  });

  test('the vocabulary is closed', () {
    // The adapter's colour table is exhaustive over exactly these. A member
    // added without a colour beside it is the failure this pins.
    expect(Role.values, [
      Role.body,
      Role.secondary,
      Role.highlight,
      Role.failure,
      Role.chrome,
    ]);
  });
}

Message _message(DateTime at) => Message(
  id: '01J000000000000000000000AA',
  author: Handle('cafe01', 'gmail.com'),
  body: 'chat is green end to end',
  spoken: at,
);

RoomTab _tab({required ActivityLevel level, required bool isCurrent}) =>
    RoomTab(
      index: 0,
      name: 'fabrica',
      isCurrent: isCurrent,
      activityLevel: level,
      activityCount: level == ActivityLevel.none ? 0 : 3,
    );
