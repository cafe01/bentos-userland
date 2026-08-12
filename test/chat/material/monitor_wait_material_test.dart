/// The material gate for `monitor --wait`'s persisted cursor — and the one
/// gate in this package that must cross a real process boundary, because
/// that boundary is the whole defect: a cursor kept in a Dart field survives
/// a second call inside one process without proving anything, since nothing
/// in production ever calls this library twice from the same `main`. The
/// compiled binary, invoked as a fresh `Process` per call, is the only
/// witness that answers whether a second invocation of `bentos.chat monitor
/// --wait` actually resumes where the first one left off.
///
///     dart test -t material test/chat/material
@Tags(['material'])
library;

import 'dart:io';

import 'package:test/test.dart';

/// Where the entity's genesis is, same convention as the channel gate.
String get chatSource =>
    Platform.environment['BENTOS_CHAT_SOURCE'] ?? '../../bentos.chat';

void main() {
  late Directory plot;
  late Directory state;
  late String exe;

  setUpAll(() {
    _demand('entity', 'the primitive is not on PATH');
    _demand('place', 'the place organ is not on PATH');
    expect(
      Directory(chatSource).existsSync(),
      isTrue,
      reason: 'no bentos.chat genesis at $chatSource — clone it, or point '
          r'$BENTOS_CHAT_SOURCE at one. This gate does not skip.',
    );

    // The real artifact, not the library called twice from one `main` — a
    // compiled binary because `dart run` recompiles on every invocation and
    // this gate makes several.
    final built = Directory.systemTemp.createTempSync('monitor-wait-build-');
    exe = '${built.path}/bentos.chat${Platform.isWindows ? '.exe' : ''}';
    final compile = Process.runSync(
      'dart',
      ['compile', 'exe', 'bin/bentos.chat.dart', '-o', exe],
    );
    if (compile.exitCode != 0) {
      fail('dart compile exe bin/bentos.chat.dart failed:\n${compile.stderr}');
    }
  });

  setUp(() {
    plot = Directory.systemTemp.createTempSync('chat-material-wait-');
    _run('place', ['init', '-n', 'material-gate'], at: plot.path);
    _run('entity', ['install', Directory(chatSource).absolute.path],
        at: plot.path);
    // Isolated per test, so this gate's cursor never touches a real $HOME and
    // two tests never share one file. **One state dir for both identities**,
    // which is the real world this gate exists to reproduce: two beings of the
    // kind run as threads on one machine, under one `$HOME`, and therefore
    // share this file. Splitting it per identity — as this fixture used to —
    // made every participant look like it owned its own state, which is
    // exactly the assumption that hid the mark being shared.
    // No repo-local git identity: that is the collision `identity.md` rules
    // out. Each process states its own voice through `$BENTOS_CHAT_IDENTITY`.
    state = Directory.systemTemp.createTempSync('monitor-wait-state-');
  });

  tearDown(() {
    plot.deleteSync(recursive: true);
    state.deleteSync(recursive: true);
  });

  const alfred = 'Alfred <alfred@bentos.life>';
  const cafe = 'Café <cafe01@gmail.com>';

  ProcessResult call(List<String> args, {String? asIdentity}) =>
      Process.runSync(
        exe,
        ['-C', plot.path, '-c', 'bentos.chat:fabrica', ...args],
        workingDirectory: plot.path,
        environment: {
          ...Platform.environment,
          'XDG_STATE_HOME': state.path,
          if (asIdentity != null) 'BENTOS_CHAT_IDENTITY': asIdentity,
        },
      );

  test('a second process resumes where the first left off — the cursor '
      'survives the process ending, not merely a second call in memory',
      () async {
    // The waiter (Alfred) and the speaker (Café) are different actors: a
    // wait is never woken by its own caller's speech, so proving this gate
    // needs a second voice, not a second process alone.
    expect(call(['join'], asIdentity: alfred).exitCode, 0);
    expect(call(['join'], asIdentity: cafe).exitCode, 0);
    expect(call(['say', 'first'], asIdentity: cafe).exitCode, 0);

    // Process one: sees "first", persists to disk, and exits — the process is
    // gone, so nothing but the file on disk carries what it learned.
    final firstProcess = call(
      ['monitor', '--wait', '--timeout', '5', '--interval', '0.1'],
      asIdentity: alfred,
    );
    expect(firstProcess.exitCode, 0,
        reason: 'stderr: ${firstProcess.stderr}');
    expect(firstProcess.stdout, contains('first'));

    expect(call(['say', 'second'], asIdentity: cafe).exitCode, 0);

    // Process two: a brand new binary invocation, with nothing of process
    // one's memory. If the cursor lived only in a field, this would see
    // "first" again — or everything since genesis. It must see only "second".
    final secondProcess = call(
      ['monitor', '--wait', '--timeout', '5', '--interval', '0.1'],
      asIdentity: alfred,
    );
    expect(secondProcess.exitCode, 0,
        reason: 'stderr: ${secondProcess.stderr}');
    expect(secondProcess.stdout, contains('second'));
    expect(secondProcess.stdout, isNot(contains('first')));

    // Process three: nothing landed since process two drained the channel.
    // Timing out — never replaying "second" — is the proof the cursor was
    // actually written and actually read back, not merely present.
    final thirdProcess = call(
      ['monitor', '--wait', '--timeout', '0.3', '--interval', '0.05'],
      asIdentity: alfred,
    );
    expect(thirdProcess.exitCode, 6, reason: 'stderr: ${thirdProcess.stderr}');
    expect(thirdProcess.stdout, isEmpty);
  });

  test('two beings sharing one state file keep separate drain marks — one '
      'speaking never consumes the other\'s delta', () {
    // The reproduction, as it happened in a real room: both participants run
    // on one machine, so one file holds both marks. Café speaks; Alfred must
    // be handed that line, whatever Café's own `say` did to Café's mark.
    expect(call(['join'], asIdentity: alfred).exitCode, 0);
    expect(call(['join'], asIdentity: cafe).exitCode, 0);

    // Both drain to the tip, so what follows is the only thing outstanding.
    // Called until quiet rather than a fixed number of times: what the joins
    // themselves put on the log is not this claim's business, and a count
    // guessed here would be a fixture asserting something it did not measure.
    void drain(String who) {
      for (var attempt = 0; attempt < 4; attempt++) {
        final r = call(
          ['monitor', '--wait', '--timeout', '0.3', '--interval', '0.05'],
          asIdentity: who,
        );
        if (r.exitCode == 6) return;
        expect(r.exitCode, 0, reason: 'stderr: ${r.stderr}');
      }
      fail('$who never reached a quiet channel');
    }

    drain(alfred);
    drain(cafe);

    // Café speaks: this advances Café's own mark past Café's line, and under
    // one key per coordinate it advanced Alfred's too — which is how a delta
    // was never delivered.
    expect(call(['say', 'anybody there?'], asIdentity: cafe).exitCode, 0);

    final alfredWait = call(
      ['monitor', '--wait', '--timeout', '5', '--interval', '0.1'],
      asIdentity: alfred,
    );
    expect(alfredWait.exitCode, 0, reason: 'stderr: ${alfredWait.stderr}');
    expect(alfredWait.stdout, contains('anybody there?'));

    // And Café is not handed back its own speech by the same file.
    final cafeWait = call(
      ['monitor', '--wait', '--timeout', '0.3', '--interval', '0.05'],
      asIdentity: cafe,
    );
    expect(cafeWait.exitCode, 6, reason: 'stderr: ${cafeWait.stderr}');

    final marks = File('${state.path}/bentos.chat/monitor-state.json')
        .readAsStringSync();
    expect(marks, contains('alfred@bentos.life'));
    expect(marks, contains('cafe01@gmail.com'));
  });
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
