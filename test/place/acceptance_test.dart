import 'package:bentos_userland/src/place/place_resolver.dart';
import 'package:bentos_userland/src/place/residence.dart';
import 'package:bentos_userland/src/place/place_runner.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  /// Run the coreutil end to end against a hermetic habitat, from [cwd].
  Future<({String out, String err, int code})> runPlace(
    Habitat hab,
    List<String> args, {
    required String cwd,
  }) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final runner = PlaceRunner(
      out: out,
      err: err,
      fileSystem: hab.fs,
      home: hab.home,
      currentDirectory: cwd,
    );
    await runner.run(args);
    return (out: out.toString(), err: err.toString(), code: runner.exitCode);
  }

  Habitat campus() {
    final hab = Habitat();
    hab.place('/home/john/hq', yaml: 'name: hq\ndescription: the wing\n');
    hab.place('/home/john/hq/cto', yaml: 'description: engineering\nowner: john\n');
    hab.place('/home/john/hq/cpo', yaml: 'description: product\nowner: alfred\n');
    hab.place('/home/john/university');
    hab.place('/home/john/university/rust');
    hab.dir('/home/john/hq/cto/.place/mem/john');
    return hab;
  }

  group('place where', () {
    test('from a deep place, prints the rooted minimap with the marker', () async {
      final r = await runPlace(campus(), ['where'], cwd: '/home/john/hq/cto');
      expect(r.code, 0);
      expect(r.out.split('\n').first, contains('(the machine)'));
      expect(r.out, contains('◄ you are here'));
      expect(r.out, contains('cto'));
    });

    test('--radius 0 still shows the chain + current', () async {
      final r = await runPlace(campus(), ['where', '--radius', '0'],
          cwd: '/home/john/hq/cto');
      expect(r.code, 0);
      expect(r.out, contains('hq'));
      expect(r.out, contains('cto'));
    });

    test('in a habitat with zero markers, still locates against / and home', () async {
      final hab = Habitat();
      hab.dir('/home/john/projects/x');
      final r = await runPlace(hab, ['where'], cwd: '/home/john/projects/x');
      expect(r.code, 0);
      expect(r.out, contains('(the machine)'));
      expect(r.out, contains('◄ you are here'));
    });
  });

  group('place tree', () {
    test('lists the subtree from the current place', () async {
      final r = await runPlace(campus(), ['tree'], cwd: '/home/john/hq');
      expect(r.code, 0);
      expect(r.out, contains('cto/   — engineering'));
      expect(r.out, contains('cpo/   — product'));
    });

    test('-t drops descriptions', () async {
      final r = await runPlace(campus(), ['tree', '-t'], cwd: '/home/john/hq');
      expect(r.code, 0);
      expect(r.out, isNot(contains('—')));
      expect(r.out, contains('cto'));
    });

    test('an explicit path argument overrides the current place', () async {
      final r = await runPlace(campus(), ['tree', '/home/john/university'],
          cwd: '/home/john/hq');
      expect(r.out, contains('rust'));
      expect(r.out, isNot(contains('cto')));
    });
  });

  group('place info', () {
    test('prints the card for the current place', () async {
      final r = await runPlace(campus(), ['info'], cwd: '/home/john/hq/cpo');
      expect(r.code, 0);
      expect(r.out, contains('cpo  — product'));
      expect(r.out, contains('owner:  alfred'));
    });
  });

  group('place who', () {
    test('lists the entity namespaces anchored at the place', () async {
      final r = await runPlace(campus(), ['who'], cwd: '/home/john/hq/cto');
      expect(r.code, 0);
      expect(r.out, contains('here:   john'));
    });

    test('--all climbs the ancestors', () async {
      final hab = campus();
      hab.dir('/home/john/hq/.place/mem/alfred');
      final r = await runPlace(hab, ['who', '--all'], cwd: '/home/john/hq/cto');
      expect(r.out, contains('alfred@hq'));
    });
  });

  group('place init', () {
    test('creates .place/place.yaml and the place is then resolvable', () async {
      final hab = campus();
      hab.dir('/home/john/hq/newroom');
      final r = await runPlace(
        hab,
        ['init', '/home/john/hq/newroom', '-o', 'john', '-d', 'a new room'],
        cwd: '/home/john/hq',
      );
      expect(r.code, 0);
      expect(r.out, contains('initialized place'));
      expect(
        Residence.markerDir(hab.fs.directory('/home/john/hq/newroom'), hab.fs)
            .existsSync(),
        isTrue,
      );
      final place = PlaceResolver(fs: hab.fs, home: hab.home)
          .enclosing('/home/john/hq/newroom');
      expect(place.owner, 'john');
      expect(place.description, 'a new room');
    });

    test('re-initializing an existing place fails cleanly (exit 1)', () async {
      final r = await runPlace(campus(), ['init', '/home/john/hq'],
          cwd: '/home/john/hq');
      expect(r.code, 1);
      expect(r.out, contains('already initialized'));
    });
  });
}
