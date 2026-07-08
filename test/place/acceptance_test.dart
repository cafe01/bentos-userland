import 'package:bentos_userland/src/place/place.dart';
import 'package:bentos_userland/src/place/place_runner.dart';
import 'package:bentos_userland/src/testing/run_in_memory_fs.dart';
import 'package:test/test.dart';

void main() {
  /// Run the coreutil end to end against a hermetic habitat, from [cwd].
  Future<({String out, String err, int code})> runPlace(
    List<String> args, {
    required String cwd,
  }) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final runner = PlaceRunner(out: out, err: err, currentDirectory: cwd);
    await runner.run(args);
    return (out: out.toString(), err: err.toString(), code: runner.exitCode);
  }

  void campus() {
    Place('/home/john/hq').create(name: 'hq', description: 'the wing');
    Place('/home/john/hq/cto').create(description: 'engineering', owner: 'john');
    Place('/home/john/hq/cpo').create(description: 'product', owner: 'alfred');
    Place('/home/john/university').create();
    Place('/home/john/university/rust').create();
  }

  group('place where', () {
    test('from a deep place, prints the rooted minimap with the marker', () {
      return runInMemoryFs((fs) async {
        campus();
        final r = await runPlace(['where'], cwd: '/home/john/hq/cto');
        expect(r.code, 0);
        expect(r.out.split('\n').first, contains('(the machine)'));
        expect(r.out, contains('◄ you are here'));
        expect(r.out, contains('cto'));
      });
    });

    test('--radius 0 still shows the chain + current', () {
      return runInMemoryFs((fs) async {
        campus();
        final r = await runPlace(['where', '--radius', '0'], cwd: '/home/john/hq/cto');
        expect(r.code, 0);
        expect(r.out, contains('hq'));
        expect(r.out, contains('cto'));
      });
    });

    test('in a habitat with zero markers, still locates against / and home', () {
      return runInMemoryFs((fs) async {
        fs.directory('/home/john/projects/x').createSync(recursive: true);
        final r = await runPlace(['where'], cwd: '/home/john/projects/x');
        expect(r.code, 0);
        expect(r.out, contains('(the machine)'));
        expect(r.out, contains('◄ you are here'));
      });
    });
  });

  group('place tree', () {
    test('lists the subtree from the current place', () {
      return runInMemoryFs((fs) async {
        campus();
        final r = await runPlace(['tree'], cwd: '/home/john/hq');
        expect(r.code, 0);
        expect(r.out, contains('cto/   — engineering'));
        expect(r.out, contains('cpo/   — product'));
      });
    });

    test('-t drops descriptions', () {
      return runInMemoryFs((fs) async {
        campus();
        final r = await runPlace(['tree', '-t'], cwd: '/home/john/hq');
        expect(r.code, 0);
        expect(r.out, isNot(contains('—')));
        expect(r.out, contains('cto'));
      });
    });

    test('an explicit path argument overrides the current place', () {
      return runInMemoryFs((fs) async {
        campus();
        final r = await runPlace(['tree', '/home/john/university'], cwd: '/home/john/hq');
        expect(r.out, contains('rust'));
        expect(r.out, isNot(contains('cto')));
      });
    });
  });

  group('place info', () {
    test('prints the card for the current place', () {
      return runInMemoryFs((fs) async {
        campus();
        final r = await runPlace(['info'], cwd: '/home/john/hq/cpo');
        expect(r.code, 0);
        expect(r.out, contains('cpo  — product'));
        expect(r.out, contains('owner:  alfred'));
      });
    });
  });

  group('place who', () {
    test('lists the tenants holding ground at the place', () {
      return runInMemoryFs((fs) async {
        campus();
        final cto = Place('/home/john/hq/cto');
        fs.directory(cto.plot('mem').path).createSync(recursive: true);
        final r = await runPlace(['who'], cwd: '/home/john/hq/cto');
        expect(r.code, 0);
        expect(r.out, contains('here:   mem'));
      });
    });

    test('--all climbs the ancestors', () {
      return runInMemoryFs((fs) async {
        campus();
        final hq = Place('/home/john/hq');
        fs.directory(hq.plot('mem').path).createSync(recursive: true);
        final r = await runPlace(['who', '--all'], cwd: '/home/john/hq/cto');
        expect(r.out, contains('mem@hq'));
      });
    });
  });

  group('place init', () {
    test('creates .place/place.yaml and the place is then resolvable', () {
      return runInMemoryFs((fs) async {
        campus();
        fs.directory('/home/john/hq/newroom').createSync(recursive: true);
        final r = await runPlace(
          ['init', '/home/john/hq/newroom', '-o', 'john', '-d', 'a new room'],
          cwd: '/home/john/hq',
        );
        expect(r.code, 0);
        expect(r.out, contains('initialized place'));
        final place = Place('/home/john/hq/newroom');
        expect(place.isImplicit, isFalse);
        expect(place.owner, 'john');
        expect(place.description, 'a new room');
      });
    });

    test('re-initializing an existing place fails cleanly (exit 1)', () {
      return runInMemoryFs((fs) async {
        campus();
        final r = await runPlace(['init', '/home/john/hq'], cwd: '/home/john/hq');
        expect(r.code, 1);
        expect(r.out, contains('already initialized'));
      });
    });
  });
}
