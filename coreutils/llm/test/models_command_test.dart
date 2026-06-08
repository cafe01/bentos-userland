import 'package:llm/llm.dart';
import 'package:llm/src/cli/commands/models_command.dart';
import 'package:test/test.dart';

void main() {
  group('ModelsCommand', () {
    late StringBuffer buf;

    setUp(() => buf = StringBuffer());

    test('exits 0', () async {
      expect(await ModelsCommand(out: buf).run(), 0);
    });

    test('lists each known device', () async {
      await ModelsCommand(out: buf).run();
      final output = buf.toString();
      for (final device in knownDevices) {
        expect(output, contains(device));
      }
    });

    test('each known device appears before the note', () async {
      await ModelsCommand(out: buf).run();
      final output = buf.toString();
      final noteIndex = output.indexOf('Note:');
      expect(noteIndex, greaterThan(0));
      for (final device in knownDevices) {
        expect(output.indexOf(device), lessThan(noteIndex));
      }
    });

    test('note mentions ls /dev/llm/ and kernel namespace enumeration', () async {
      await ModelsCommand(out: buf).run();
      final output = buf.toString();
      expect(output, contains('ls /dev/llm/'));
      expect(output, contains('kernel namespace enumeration'));
    });

    test('registered in LlmRunner', () {
      expect(LlmRunner().commands.keys, contains('models'));
    });
  });
}
