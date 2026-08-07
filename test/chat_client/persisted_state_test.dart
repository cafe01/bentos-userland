import 'dart:io';

import 'package:bentos_userland/src/chat_client/persisted_state.dart';
import 'package:test/test.dart';

void main() {
  group('PersistedState', () {
    late Directory tmp;
    late File file;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('chat-state-test');
      file = File('${tmp.path}/state.json');
    });

    tearDown(() {
      tmp.deleteSync(recursive: true);
    });

    test('load with no file starts empty rather than refusing to run', () {
      final state = PersistedState.load(file: file);
      expect(state.of('bentos.chat:fabrica').readMark, isNull);
      expect(state.of('bentos.chat:fabrica').sentHistory, isEmpty);
    });

    test('save then load round-trips a room and the current coordinate', () {
      final state = PersistedState();
      state.rooms['bentos.chat:fabrica'] =
          const RoomState(readMark: 'm-1', sentHistory: ['status?', 'ok']);
      state.currentCoordinate = 'bentos.chat:fabrica';
      state.save(file: file);

      final reloaded = PersistedState.load(file: file);

      expect(reloaded.currentCoordinate, 'bentos.chat:fabrica');
      expect(reloaded.of('bentos.chat:fabrica').readMark, 'm-1');
      expect(reloaded.of('bentos.chat:fabrica').sentHistory, ['status?', 'ok']);
    });

    test('a corrupt file starts fresh rather than crashing', () {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('not json');

      final state = PersistedState.load(file: file);

      expect(state.rooms, isEmpty);
    });

    test('writes the parent directory when it does not exist yet', () {
      final nested = File('${tmp.path}/a/b/state.json');
      PersistedState().save(file: nested);
      expect(nested.existsSync(), isTrue);
    });
  });
}
