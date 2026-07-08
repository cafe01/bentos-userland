import 'dart:io';

import 'package:bentos_userland/src/mem2/body_source.dart';
import 'package:bentos_userland/src/testing/run_in_memory_fs.dart';
import 'package:test/test.dart';

void main() {
  group('BodySource', () {
    test('reads from stdin when no --file', () {
      runInMemoryFs((fs) {
        final src = BodySource(stdinContent: 'the body');
        expect(src.read(), 'the body');
      });
    });

    test('reads from --file when given, over stdin', () {
      runInMemoryFs((fs) {
        File('/note.md').writeAsStringSync('file body');
        final src = BodySource(stdinContent: 'stdin body');
        expect(src.read(filePath: '/note.md'), 'file body');
      });
    });

    test('--file on a missing path errors cleanly', () {
      runInMemoryFs((fs) {
        final src = BodySource(stdinContent: 'x');
        expect(() => src.read(filePath: '/nope.md'), throwsA(isA<FileSystemException>()));
      });
    });

    test('an absent body on remember errors, never a silent no-op', () {
      runInMemoryFs((fs) {
        expect(() => BodySource().read(), throwsA(isA<BodyMissing>()));
      });
    });

    test('a whitespace-only body errors too', () {
      runInMemoryFs((fs) {
        expect(() => BodySource(stdinContent: '  \n\t ').read(),
            throwsA(isA<BodyMissing>()));
      });
    });
  });
}
