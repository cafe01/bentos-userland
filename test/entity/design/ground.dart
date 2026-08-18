/// The ground the design suite stands on: three copies of one entity on one
/// disk — a hub at a bare address, and copies A and B in two directories.
///
/// Two rules for the whole suite (design §5): **no test reaches the network**
/// — the hub is a bare repository on the same disk and every address is a
/// path — and **every test that asserts a standing asserts its age**, through
/// [expectStanding] and nothing else.
library;

import 'dart:io';

import 'package:bentos_userland/src/entity/contract/contract.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const Actor alice = Actor(name: 'alice', address: 'alice@test.local');
const Actor bob = Actor(name: 'bob', address: 'bob@test.local');

/// The name of the first source on every copy stood from the hub.
const String hub = 'hub';

/// The thing under test. Its rhythm makes the hub publish-to and follow, by
/// hand, so no cadence fires behind a test's back.
const Manifest thing = Manifest(
  name: 'suite.chat',
  kind: 'chat',
  instanceName: InstanceNaming(fallback: 'untitled'),
  rhythm: Rhythm(roles: {Role.publishTo, Role.follow}, cadence: ByHand()),
);

/// Where the suite's temporary ground lives — `$TMPDIR` when set, so parallel
/// work stays off a small root.
Directory scratch(String label) {
  final base = Platform.environment['TMPDIR'];
  final parent = base == null ? Directory.systemTemp : Directory(base);
  return parent.createTempSync('entity-design-$label-');
}

/// A bare repository at a path: the hub. Made with git directly, because a
/// hub is not a copy — it has no plot and nobody acts on it.
String bareHub(Directory root) {
  final path = p.join(root.path, 'hub.git');
  final r = Process.runSync('git', ['init', '--bare', '--quiet', path]);
  if (r.exitCode != 0) throw StateError('git init --bare failed: ${r.stderr}');
  return path;
}

/// One machine, three copies. [A] authored the thing and published it to the
/// hub; [B] stood from the hub. Both hold the hub as source [hub].
final class Ground {
  Ground._(this.root, this.hubAddress, this.a, this.b);

  final Directory root;
  final String hubAddress;
  final Copy a;
  final Copy b;

  /// Every ground stood since the last [disposeGrounds]. A ground whose
  /// standing failed midway is disposed here too, so a red suite leaves no
  /// residue under `$TMPDIR`.
  static final List<Ground> _standing = [];

  static Future<Ground> stand({Manifest manifest = thing}) async {
    final root = scratch('ground');
    try {
      return await _stand(root, manifest);
    } catch (_) {
      if (root.existsSync()) root.deleteSync(recursive: true);
      rethrow;
    }
  }

  static Future<Ground> _stand(Directory root, Manifest manifest) async {
    final address = bareHub(root);
    final a = await Copy.author(
      name: manifest.name,
      at: Directory(p.join(root.path, 'a', 'copy')),
      plot: Directory(p.join(root.path, 'a', 'plot')),
      by: alice,
      manifest: manifest,
    );
    a.addSource(Source(
      name: hub,
      address: address,
      roles: manifest.rhythm.roles,
      cadence: manifest.rhythm.cadence,
    ));
    // The class itself must reach the hub before anyone can stand from it.
    await a.moveClass(source: hub, direction: Direction.publish);
    final b = await Copy.stand(
      address,
      at: Directory(p.join(root.path, 'b', 'copy')),
      plot: Directory(p.join(root.path, 'b', 'plot')),
    );
    final ground = Ground._(root, address, a, b);
    _standing.add(ground);
    return ground;
  }

  /// A fresh directory under this ground, for a materialization or a second
  /// copy.
  Directory dir(String name) =>
      Directory(p.join(root.path, name))..createSync(recursive: true);

  /// Cut the network: the hub stops existing at its address. On one disk that
  /// is the only honest way to make a source unreachable.
  void cutHub() => Directory(hubAddress).renameSync('$hubAddress.cut');
  void restoreHub() => Directory('$hubAddress.cut').renameSync(hubAddress);

  void dispose() {
    if (root.existsSync()) root.deleteSync(recursive: true);
    _standing.remove(this);
  }
}

/// Dispose every ground stood by the current test. The tearDown every file
/// registers, so that a ground whose standing failed does not leak and a
/// `late` handle that was never set does not turn one red into two.
void disposeGrounds() {
  for (final g in List.of(Ground._standing)) {
    g.dispose();
  }
}

/// The one file the primitive reads, and the only thing this suite assumes
/// about the class's layout. Its schema grows by concrete use and no page
/// fixes it; the shape written here is the running primitive's, extended.
const String declarationFile = 'entity.yaml';

String declarationOf(Manifest m) {
  final b = StringBuffer()
    ..writeln('name: ${m.name}')
    ..writeln('kind: ${m.kind}')
    ..writeln('instance-name:')
    ..writeln('  fallback: ${m.instanceName.fallback}')
    ..writeln('rhythm:')
    ..writeln('  roles: [${m.rhythm.roles.map((r) => r.name).join(', ')}]')
    ..writeln('  cadence: by-hand');
  if (m.functions.isNotEmpty) {
    b.writeln('functions:');
    m.functions.forEach((k, v) => b.writeln('  $k: \'$v\''));
  }
  return b.toString();
}

/// Change the declaration standing on [copy] to [manifest], the only way a
/// line changes: an action on the class (`Copy.actOnClass`).
Future<Outcome> declare(Copy copy, Manifest manifest, {required Actor by}) =>
    copy.actOnClass((act) => write(act, declarationFile, declarationOf(manifest)),
        by: by, say: 'declared');

/// Write [content] at [path] inside an act's private area.
void write(Act act, String path, String content) {
  File(p.join(act.directory.path, path))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}

/// Land one action on [instance]: write [path], land with [say] and [title].
Future<Outcome> land(
  Instance instance, {
  required Actor by,
  String path = 'messages/1.txt',
  String content = 'hello',
  String? say,
  String? title,
}) =>
    instance.act((act) => write(act, path, content),
        by: by, say: say, title: title);

/// Land and insist it landed.
Future<Action> landed(
  Instance instance, {
  required Actor by,
  String path = 'messages/1.txt',
  String content = 'hello',
  String? say,
  String? title,
}) async {
  final outcome = await land(instance,
      by: by, path: path, content: content, say: say, title: title);
  expect(outcome, isA<Landed>(), reason: 'expected the landing to land');
  return (outcome as Landed).action;
}

/// The one way this suite asserts a standing. A relation is asserted with
/// its counts **and its age**: every value but `unknown` must carry when the
/// contact it rests on happened, and `unknown` must carry none (R2.9.1a,
/// R2.9.2). A suite that let an undated standing pass would have let the
/// running implementation pass.
void expectStanding(
  Standing standing,
  Relation relation, {
  int behind = 0,
  int ahead = 0,
  Instant? notBefore,
  Instant? notAfter,
  String? reason,
}) {
  expect(standing.relation, relation, reason: reason);
  expect(standing.behind, behind, reason: 'behind count — $reason');
  expect(standing.ahead, ahead, reason: 'ahead count — $reason');
  if (relation == Relation.unknown) {
    expect(standing.contacted, isNull,
        reason: 'unknown is the one value that carries no age');
    return;
  }
  expect(standing.contacted, isNotNull,
      reason: 'a standing without an age is not an answer');
  final age = standing.contacted!;
  if (notBefore != null) {
    expect(age.isBefore(notBefore), isFalse,
        reason: 'the age must not predate the contact it rests on');
  }
  if (notAfter != null) {
    expect(age.isAfter(notAfter), isFalse,
        reason: 'the age must not postdate the last contact');
  }
}
