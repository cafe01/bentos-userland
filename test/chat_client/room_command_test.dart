import 'package:bentos_userland/src/chat_client/intent.dart';
import 'package:bentos_userland/src/chat_client/room_command.dart';
import 'package:test/test.dart';

RoomCommand _resolve(String verb, [List<String> args = const []]) =>
    resolveCommand(InvokeCommand(verb, args));

void main() {
  group('resolveCommand', () {
    test('join with no argument means the current room', () {
      final command = _resolve('join') as JoinRoom;
      expect(command.coordinate, isNull);
    });

    test('join with an argument names a coordinate to open', () {
      final command = _resolve('join', ['design']) as JoinRoom;
      expect(command.coordinate, 'design');
    });

    test('leave takes no argument', () {
      expect(_resolve('leave'), isA<LeaveRoom>());
    });

    test('away with no words means no reason', () {
      final command = _resolve('away') as SetAway;
      expect(command.reason, isNull);
    });

    test('away rejoins its words into one reason', () {
      final command = _resolve('away', ['lunch', 'with', 'the', 'team']) as SetAway;
      expect(command.reason, 'lunch with the team');
    });

    test('back takes no argument', () {
      expect(_resolve('back'), isA<SetBack>());
    });

    test('bare topic means read, never write', () {
      expect(_resolve('topic'), isA<ShowTopic>());
    });

    test('topic with words means write, rejoined into one text', () {
      final command = _resolve('topic', ['the', 'factory', 'floor']) as SetTopic;
      expect(command.text, 'the factory floor');
    });

    test('list and channels are the same command', () {
      expect(_resolve('list'), isA<ListChannels>());
      expect(_resolve('channels'), isA<ListChannels>());
    });

    test('help', () {
      expect(_resolve('help'), isA<ShowHelp>());
    });

    test('an unwired verb resolves to a value, never throws', () {
      final command = _resolve('mute', ['here']) as UnknownCommand;
      expect(command.verb, 'mute');
      expect(command.args, ['here']);
    });
  });
}
