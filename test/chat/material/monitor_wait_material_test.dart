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
  late Directory alfredState;
  late Directory cafeState;
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
    // two tests never share one file. **One state dir per identity**, since
    // `say` now advances its own speaker's persisted cursor too: two
    // identities sharing one state file would have each one's `say`
    // clobbering the other's read mark, which is not the real world — every
    // participant runs from its own `$HOME`.
    // No repo-local git identity: that is the collision `identity.md` rules
    // out. Each process states its own voice through `$BENTOS_CHAT_IDENTITY`.
    alfredState = Directory.systemTemp.createTempSync('monitor-wait-state-alfred-');
    cafeState = Directory.systemTemp.createTempSync('monitor-wait-state-cafe-');
  });

  tearDown(() {
    plot.deleteSync(recursive: true);
    alfredState.deleteSync(recursive: true);
    cafeState.deleteSync(recursive: true);
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
          'XDG_STATE_HOME':
              asIdentity == cafe ? cafeState.path : alfredState.path,
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
