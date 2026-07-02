import 'package:bentos_userland/src/mem2/body_source.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

void main() {
  group('BodySource', () {
    late FileSystem fs;

    setUp(() => fs = MemoryFileSystem());

    test('reads from stdin when no --file', () {
      final src = BodySource(fs: fs, stdinContent: 'the body');
      expect(src.read(), 'the body');
    });

    test('reads from --file when given, over stdin', () {
      fs.file('/note.md').writeAsStringSync('file body');
      final src = BodySource(fs: fs, stdinContent: 'stdin body');
      expect(src.read(filePath: '/note.md'), 'file body');
    });

    test('--file on a missing path errors cleanly', () {
      final src = BodySource(fs: fs, stdinContent: 'x');
      expect(() => src.read(filePath: '/nope.md'), throwsA(isA<FileSystemException>()));
    });

    test('an absent body on remember errors, never a silent no-op', () {
      expect(() => BodySource(fs: fs).read(), throwsA(isA<BodyMissing>()));
    });

    test('a whitespace-only body errors too', () {
      expect(() => BodySource(fs: fs, stdinContent: '  \n\t ').read(),
          throwsA(isA<BodyMissing>()));
    });
  });
}
