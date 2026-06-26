import 'package:file/memory.dart';
import 'package:bentos_userland/src/mem/body_source.dart';
import 'package:test/test.dart';

void main() {
  late MemoryFileSystem fs;

  setUp(() => fs = MemoryFileSystem());

  group('BodySource', () {
    test('reads from --file when given', () async {
      fs.file('/content/page.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('the page body\n');

      final source = BodySource(fs);
      final result = await source.read(filePath: '/content/page.md');
      expect(result, 'the page body\n');
    });

    test('--file on missing path errors cleanly (does not silently swallow)', () async {
      final source = BodySource(fs);
      expect(
        () => source.read(filePath: '/no/such/file.md'),
        throwsA(isNot(isA<UnimplementedError>())),
        reason: 'missing file must raise an informative error, not silently return empty',
      );
    });

    test('no --file reads from stdin', () async {
      // stdin injection interface TBD — the current StringSink? stdinSink
      // parameter is a naming placeholder; this test documents the contract.
      // When implemented, BodySource must read from the process stdin stream.
      final source = BodySource(fs);
      // In the red phase this throws UnimplementedError; test is RED.
      final result = await source.read();
      expect(result, isA<String>(), reason: 'stdin path must return a String');
    });
  });
}
