import 'dart:io';

import 'package:bentos_userland/src/mem2/body_source.dart';
import 'package:bentos_userland/src/testing/run_in_memory_fs.dart';
import 'package:test/test.dart';

void main() {
  group('BodySource', () {
    test('reads from stdin when no --file', () async {
      await runInMemoryFs((fs) async {
        final src = BodySource(stdinReader: () async => 'the body');
        expect(await src.read(), 'the body');
      });
    });

    test('reads from --file when given, over stdin', () async {
      await runInMemoryFs((fs) async {
        File('/note.md').writeAsStringSync('file body');
        final src = BodySource(stdinReader: () async => 'stdin body');
        expect(await src.read(filePath: '/note.md'), 'file body');
      });
    });

    test('--file never touches stdin — the reader is not even called', () async {
      await runInMemoryFs((fs) async {
        File('/note.md').writeAsStringSync('file body');
        var drained = false;
        final src = BodySource(stdinReader: () async {
          drained = true;
          return 'stdin body';
        });
        await src.read(filePath: '/note.md');
        expect(drained, isFalse);
      });
    });

    test('--file on a missing path errors cleanly', () async {
      await runInMemoryFs((fs) async {
        final src = BodySource(stdinReader: () async => 'x');
        expect(src.read(filePath: '/nope.md'), throwsA(isA<FileSystemException>()));
      });
    });

    test('an absent body on remember errors, never a silent no-op', () async {
      await runInMemoryFs((fs) async {
        expect(BodySource().read(), throwsA(isA<BodyMissing>()));
      });
    });

    test('a whitespace-only body errors too', () async {
      await runInMemoryFs((fs) async {
        expect(BodySource(stdinReader: () async => '  \n\t ').read(),
            throwsA(isA<BodyMissing>()));
      });
    });
  });
}
