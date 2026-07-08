import 'dart:io';

import 'package:bentos_userland/src/testing/run_in_memory_fs.dart';
import 'package:test/test.dart';

void main() {
  group('runInMemoryFs bridge', () {
    test('a bare File constructed inside the zone reads/writes the MemoryFileSystem', () {
      late String seenOutside;
      runInMemoryFs((fs) {
        // BEHAVIOR:
        File('/note.txt').writeAsStringSync('hello');
        // VERIFY:
        expect(fs.file('/note.txt').readAsStringSync(), 'hello',
            reason: 'bare File writes land in the injected MemoryFileSystem');
        seenOutside = fs.file('/note.txt').path;
      });
      expect(File(seenOutside).existsSync(), isFalse,
          reason: 'the in-memory write never touches the real disk');
    });

    test('a bare Directory constructed inside the zone reads the MemoryFileSystem', () {
      runInMemoryFs((fs) {
        fs.directory('/seeded').createSync(recursive: true);
        expect(Directory('/seeded').existsSync(), isTrue,
            reason: 'bare Directory reads the injected filesystem');
      });
    });

    test('Directory.current inside the zone is the installed home', () {
      runInMemoryFs((fs) {
        expect(Directory.current.path, '/home/john',
            reason: 'home is installed as the working directory');
      }, home: '/home/john');
    });

    test('Directory.current honors a custom home', () {
      runInMemoryFs((fs) {
        expect(Directory.current.path, '/home/mary', reason: 'custom home is respected');
      }, home: '/home/mary');
    });

    test('nesting: a directory created bare is visible via fs', () {
      runInMemoryFs((fs) {
        Directory('/x').createSync();
        expect(fs.directory('/x').existsSync(), isTrue,
            reason: 'bare dart:io writes are visible through the fs handle');
      });
    });

    test('outside the zone the real disk applies', () {
      final realTemp = Directory.systemTemp.path;
      runInMemoryFs((fs) {
        expect(Directory.systemTemp.path, isNot(realTemp),
            reason: 'inside the zone systemTemp is the in-memory stand-in');
      });
      expect(Directory.systemTemp.path, realTemp,
          reason: 'outside the zone the real disk temp dir is restored');
    });

    test('a probe of the in-memory path fails outside the zone', () {
      late String path;
      runInMemoryFs((fs) {
        fs.directory('/only/in/memory').createSync(recursive: true);
        path = '/only/in/memory';
      });
      expect(Directory(path).existsSync(), isFalse,
          reason: 'the in-memory directory does not exist on the real disk');
    });
  });
}
