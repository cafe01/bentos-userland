/// The identity gate: **who is speaking**, over the real faces.
///
/// [The design page](mem://alfred.mem/domain/bentos/userland/chat/design-specification/identity)
/// names six proofs. Four of them live here, because the class of defect they
/// answer is invisible to a double: a fixture *supplies* an identity and never
/// asks where a real one comes from, which is exactly why the suite stayed
/// green through both collapses — the medium answering (08/12) and the machine
/// answering (08/13).
///
/// * **1** — silence is refused, on every face, *with the machine's git
///   cascade fully configured and reachable*. The control is the gate: an
///   absent cascade over-determines the refusal and proves nothing.
/// * **3** — a mind at the command line and a human at the screen's own floor,
///   one installation, each attributed to its own row.
/// * **4** — an arrival claiming a local part held by a different address is
///   refused, naming the seated address.
/// * **5** — a bare address and a bare name are each refused, with the form.
///
/// **2** — two actors of different identity, each line signed by its own
/// author — is proven in `channel_material_test.dart`, where the apparatus for
/// two writers over one real tree already stands. **6** — no source under
/// `lib/src/chat/` reads a git cascade — is a grep, needs no binaries, and
/// runs in the default suite: `test/chat/identity_source_test.dart`.
///
/// **It fails when the pieces are absent; it never skips.**
///
///     dart test -t material test/chat/material/identity_material_test.dart
///
@Tags(['material'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:bentos_userland/bentos_chat.dart';
import 'package:bentos_userland/entity.dart' show Entity;
import 'package:bentos_userland/mcp.dart' show Program;
import 'package:dart_mcp/server.dart' show CallToolRequest;
import 'package:test/test.dart';

import '../../mcp/support/harness.dart' show ServerHarness, partsOf;

/// Where the entity's genesis is. An environment variable so the gate does not
/// presume a campus: any clone of `bentos.chat` answers.
String get chatSource =>
    Platform.environment['BENTOS_CHAT_SOURCE'] ?? '../../bentos.chat';

/// The package root — the faces are run from source, never from whatever is
/// installed on this machine, which may be older than the claim under judgment.
final String packageRoot = Directory.current.absolute.path;

void main() {
  late Directory plot;

  setUpAll(() {
    _demand('entity', 'the primitive is not on PATH');
    _demand('place', 'the place organ is not on PATH');
    _demand('git', 'git is not on PATH');
    expect(
      Directory(chatSource).existsSync(),
      isTrue,
      reason: 'no bentos.chat genesis at $chatSource — clone it, or point '
          r'$BENTOS_CHAT_SOURCE at one. This gate does not skip.',
    );
  });

  setUp(() {
    plot = Directory.systemTemp.createTempSync('chat-identity-');
    _run('place', ['init', '-n', 'identity-gate'], at: plot.path);
    _run('entity', ['install', Directory(chatSource).absolute.path],
        at: plot.path);
  });

  tearDown(() => plot.deleteSync(recursive: true));

  /// A channel as the screen builds one: `EntityFloor` is what `bin/chat.dart`
  /// constructs the instant it has resolved a value, so this is the screen's
  /// own floor with the terminal left off.
  Channel screenChannel(String name, Identity identity) =>
      EntityFloor(identity: identity).channel(name, place: plot.path);

  group('gate 1 — a caller that states nothing is refused, on every face', () {
    // THE CONTROL. The cascade this machine would have answered with must be
    // present and reachable *inside the gate*: a refusal recorded against an
    // unconfigured git is a refusal that proves nothing, because there was
    // nothing available to wrongly answer with. This is the assert the first
    // gate never had.
    setUp(() {
      final name = _git(['config', '--get', 'user.name'], at: plot.path);
      final email = _git(['config', '--get', 'user.email'], at: plot.path);
      expect(
        name,
        isNotEmpty,
        reason: 'no user.name on this machine — the silence being refused '
            'below would be over-determined. This gate does not skip.',
      );
      expect(email, isNotEmpty, reason: 'no user.email on this machine — same');
    });

    // The 08/13 caller exactly: BENTOS_AGENT unset, so nothing about who is
    // asking is on offer. The refusal is unconditional and must not need it.
    final silentCaller = _environmentWithout(['BENTOS_AGENT', identityVariable]);

    test('the command line refuses with 64, and prints the flag, the variable '
        'and the form', () {
      final r = _face(
        'bin/bentos.chat.dart',
        ['-C', plot.path, '-c', 'fabrica', 'join'],
        environment: silentCaller,
      );

      // 64 and not 3: the command was not sayable, so a retry loop must stop
      // rather than try again at something that can never work.
      expect(r.exitCode, 64);
      expect(r.stderr, contains('--identity'));
      expect(r.stderr, contains(identityVariable));
      expect(r.stderr, contains('Name <addr>'));

      // And nothing landed under the machine's name.
      expect(
        _refs(plot),
        isNot(contains('fabrica')),
        reason: 'a refused arrival must not have founded a channel',
      );
    });

    test('the screen does not open, and answers on stderr rather than with a '
        'dialog or a stack trace', () {
      final r = _face(
        'bin/chat.dart',
        ['-C', plot.path, 'fabrica'],
        environment: silentCaller,
      );

      expect(r.exitCode, 64);
      expect(r.stderr, contains('Name <addr>'));
      expect(
        r.stderr,
        isNot(contains('#0')),
        reason: 'a stack trace where a refusal belongs is the screen having no '
            'way to state an identity at all',
      );
    });

    test("the model's face carries the program's own exit and sentence, so a "
        'mind reads what a human reads', () async {
      // `mcp` is a server, not a one-shot wrapper: the mind's call is a
      // `tools/call` over the protocol, so that is how the claim is asked.
      // The shim is what the wrapper spawns — the face **from source**, with
      // the two names this gate is proving nobody may lean on stripped from
      // the environment before the program ever starts.
      final shim = File('${plot.path}/bentos.chat')
        ..writeAsStringSync('#!/bin/sh\n'
            'unset BENTOS_AGENT $identityVariable\n'
            'exec "$_dart" run "$packageRoot/bin/bentos.chat.dart" "\$@"\n');
      Process.runSync('chmod', ['+x', shim.path]);

      final harness = ServerHarness(await Program.prepare(shim.path));
      await harness.initialize();

      // Whatever the wrapper called it: the tool's name is its business, and
      // asking the listing keeps this gate about identity.
      final tool = (await harness.connection.listTools()).tools.single;

      final result = await harness.connection.callTool(
        CallToolRequest(
          name: tool.name,
          arguments: {
            'args': ['-C', plot.path, '-c', 'fabrica', 'join'],
            'timeout': 120000,
          },
        ),
      );

      final parts = partsOf(result);
      expect(result.isError, isTrue);
      expect(parts[0], contains('64'),
          reason: 'the mind must read the program\'s own number, not the '
              'wrapper\'s opinion of it');
      expect(parts.join('\n'), contains('Name <addr>'));
      expect(_refs(plot), isNot(contains('fabrica')));
    });
  });

  test('gate 5 — a bare address and a bare name are each refused, with the '
      'form printed', () {
    for (final half in ['peer@bentos.life', 'Peer']) {
      final r = _face(
        'bin/bentos.chat.dart',
        ['-C', plot.path, '-c', 'fabrica', '-I', half, 'join'],
      );

      expect(r.exitCode, 64, reason: 'half an identity is not an identity: $half');
      expect(r.stderr, contains('Name <addr>'));
    }

    // Neither half alone signed anything: no channel was founded at all.
    expect(_refs(plot), isNot(contains('fabrica')));
  });

  test('gate 4 — an arrival claiming a local part held by a different address '
      'is refused, naming the seated address', () async {
    final seated = _face('bin/bentos.chat.dart', [
      '-C', plot.path, '-c', 'fabrica',
      '-I', 'Alfred <alfred@bentos.life>', 'join',
    ]);
    expect(seated.exitCode, 0, reason: seated.stderr as String);

    // Same word in this conversation, a different being behind it. This is the
    // 08/12 collapse arriving through the front door.
    final impostor = _face('bin/bentos.chat.dart', [
      '-C', plot.path, '-c', 'fabrica',
      '-I', 'Alfred <alfred@example.com>', 'join',
    ]);

    expect(impostor.exitCode, 3, reason: 'somebody refused — not a usage error');
    expect(
      impostor.stderr,
      contains('alfred@bentos.life'),
      reason: 'the refusal must name the address already seated, or the caller '
          'cannot tell a collision from a bug',
    );

    // The roster still holds exactly one being under that word.
    final roster = _face('bin/bentos.chat.dart', [
      '-C', plot.path, '-c', 'fabrica',
      '-I', 'Alfred <alfred@bentos.life>', 'roster',
    ]);
    expect(
      const LineSplitter().convert(roster.stdout as String)
          .where((l) => l.contains('@alfred'))
          .length,
      1,
    );
  });

  test('gate 3 — a mind at the command line and a human at the screen, one '
      'installation, each attributed to its own row', () async {
    // The human, through the floor `bin/chat.dart` builds the instant it has
    // resolved a value. The window is the only part left off: what is under
    // judgment is attribution, and the terminal has no opinion about it.
    final human = _GateIdentity(Handle.ofEmail('cafe01@gmail.com'), 'Café');
    final screen = screenChannel('fabrica', human);
    expect(await screen.join(displayName: 'Café'), isA<Acted>());
    expect(await screen.say('sitting at the window'), isA<Acted>());

    // The mind, through the face it is handed — stating its own name, which is
    // not derived from anything on this box.
    final mind = _face('bin/bentos.chat.dart', [
      '-C', plot.path, '-c', 'fabrica',
      '-I', 'Alfred <alfred@bentos.life>', 'join',
    ]);
    expect(mind.exitCode, 0, reason: mind.stderr as String);
    final spoke = _face('bin/bentos.chat.dart', [
      '-C', plot.path, '-c', 'fabrica',
      '-I', 'Alfred <alfred@bentos.life>', 'say', 'reading the room',
    ]);
    expect(spoke.exitCode, 0, reason: spoke.stderr as String);

    // Two rows, two beings — the 08/12 record showed one.
    final roster = await screen.roster();
    expect(
      roster.participants.map((p) => p.handle.email).toSet(),
      {'cafe01@gmail.com', 'alfred@bentos.life'},
    );

    // And each line is signed by whoever said it, in the entity's own history.
    final transcript = await screen.history();
    expect(
      {for (final m in transcript) m.body: m.author.email},
      {
        'sitting at the window': 'cafe01@gmail.com',
        'reading the room': 'alfred@bentos.life',
      },
    );
  });
}

/// Runs one of the real faces from source, in this package, against [plot].
///
/// From source and never from `~/.local/bin`: what is installed is not always
/// what is being judged.
ProcessResult _face(
  String entrypoint,
  List<String> arguments, {
  Map<String, String>? environment,
}) =>
    Process.runSync(
      _dart,
      ['run', entrypoint, ...arguments],
      workingDirectory: packageRoot,
      environment: environment ?? _environmentWithout([identityVariable]),
      includeParentEnvironment: false,
    );

String get _dart => Platform.resolvedExecutable;

/// The caller's real environment, minus the names this gate is proving nobody
/// may lean on. `includeParentEnvironment: false` everywhere, so what a face
/// sees is exactly this map and never the harness's leftovers.
Map<String, String> _environmentWithout(List<String> names) => {
      for (final e in Platform.environment.entries)
        if (!names.contains(e.key)) e.key: e.value,
    };

/// The channels that actually exist: the entity's own refs, genesis excluded.
/// A refused arrival must leave this list untouched.
List<String> _refs(Directory plot) => Entity('bentos.chat', from: plot.path)
    .instances
    .map((i) => i.id)
    .toList(growable: false);

String _git(List<String> arguments, {required String at}) {
  final r = Process.runSync('git', arguments, workingDirectory: at);
  return (r.stdout as String).trim();
}

final class _GateIdentity implements Identity {
  const _GateIdentity(this.handle, this.displayName);

  @override
  final Handle handle;

  @override
  final String displayName;
}

void _demand(String binary, String complaint) {
  final found = Process.runSync(
    Platform.isWindows ? 'where' : 'which',
    [binary],
  );
  expect(found.exitCode, 0, reason: '$complaint. This gate does not skip.');
}

String _run(String binary, List<String> arguments, {required String at}) {
  final r = Process.runSync(binary, arguments, workingDirectory: at);
  if (r.exitCode != 0) {
    fail('$binary ${arguments.join(' ')} → ${r.exitCode}\n${r.stderr}');
  }
  return r.stdout as String;
}
