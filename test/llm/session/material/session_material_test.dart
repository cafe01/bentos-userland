/// The material gate: the real floor, driven by real binaries.
///
/// Everything in `contract_suite.dart` is judged against doubles, and a double
/// is blind to exactly one thing — the seam between this package and the floor
/// it stands on. Here the witness is a real `entity`, the real `bentos.llm`
/// bodies, a real Git tree and a real device. Nothing in this file is minted by
/// the code under judgment.
///
/// **It fails when the pieces are absent; it never skips.** A gate that rescues
/// itself is the polite form of the empty assert, and the day this one starts
/// skipping is the day it stops being a gate. That is also why it carries its
/// own tag and runs on its own target, away from the suite that runs fifty
/// times a day: fragility there is what buys a `skip` request.
///
///     dart test -t material test/llm/session/material
///
/// Owed, and named rather than solved here: this target is declared in no
/// release path yet, and a material gate that runs nowhere is decoration.
@Tags(['material'])
library;

import 'dart:io';

import 'package:test/test.dart';

/// Where the entity's genesis is. An environment variable so the gate does not
/// presume a campus: any clone of `bentos.llm` answers.
String get llmSource =>
    Platform.environment['BENTOS_LLM_SOURCE'] ?? '../../bentos.llm';

const String fixtureDevice = '/dev/llm/fixture/echo';

void main() {
  late Directory plot;

  setUpAll(() {
    _demand('entity', 'the primitive is not on PATH');
    _demand('place', 'the place organ is not on PATH');
    expect(
      Directory(llmSource).existsSync(),
      isTrue,
      reason: 'no bentos.llm genesis at $llmSource — clone it, or point '
          r'$BENTOS_LLM_SOURCE at one. This gate does not skip.',
    );
  });

  setUp(() {
    plot = Directory.systemTemp.createTempSync('llm-session-material-');
    _run('place', ['init', '-n', 'material-gate'], at: plot.path);
    _run('entity', ['install', Directory(llmSource).absolute.path],
        at: plot.path);
  });

  tearDown(() => plot.deleteSync(recursive: true));

  test('open · say · reply · rest, against a device that needs no credential',
      () {
    const coord = 'bentos.llm:gate';

    _run('entity', ['run', coord, 'user.open', '--device', fixtureDevice],
        at: plot.path);

    // The arming is on loan from `install`, exactly as the client does it
    // today; when the manifest's `on:` table is read at install, these three
    // lines go and nothing else in this gate changes.
    for (final (event, function) in const [
      ('prompt.landed', 'assistant.reply'),
      ('function-result.landed', 'assistant.reply'),
      ('reply.landed', 'executor.run'),
    ]) {
      _run(
        'entity',
        ['on', coord, event, '--', 'entity', '-C', plot.path, 'run', coord, function],
        at: plot.path,
      );
    }

    _run('entity', ['run', coord, 'user.say', 'olá'], at: plot.path);

    final state = _restedWithin(const Duration(seconds: 60), coord, plot.path);
    expect(state, 'idle', reason: 'the circuit never came back to rest');

    final names = _run('entity', ['ls', '$coord:llm/messages'], at: plot.path)
        .split('\n')
        .where((l) => l.trim().isNotEmpty && !l.endsWith('.gitkeep'))
        .toList();
    expect(names.length, greaterThanOrEqualTo(3),
        reason: 'system, prompt and a reply should stand in the tree');
    expect(names.last, endsWith('.jsonl'),
        reason: "an assistant's turn lands as its event stream");

    // The log's columns are the floor's own: sha, PAYLOAD NOUN, actor, instant,
    // sentence. It never carries the function's name — the noun is all the
    // substrate reads, and the verb survives only inside the sentence a person
    // is shown. Asserting the pair (noun, actor) is the stronger claim anyway:
    // it says the reply was authored by the assistant and the prompt by the
    // user, which a search for a function name never said.
    //
    // The lines with an EMPTY noun are the class's own authoring commits
    // leaking into every instance's log — a defect of `entity log` recorded on
    // the primitive's front, and the reason `EntityPrimitive.log` drops them.
    final acts = [
      for (final line in _run('entity', ['log', coord], at: plot.path).split('\n'))
        if (line.split('\t') case [_, final noun, final actor, ...])
          if (noun.trim().isNotEmpty) (noun, actor)
    ];
    expect(acts, contains(('reply', 'assistant')));
    expect(acts, contains(('prompt', 'user')));
  });
}

void _demand(String binary, String complaint) {
  final found = Process.runSync(
    Platform.isWindows ? 'where' : 'which',
    [binary],
  );
  expect(found.exitCode, 0, reason: '$complaint. This gate does not skip.');
}

String _restedWithin(Duration limit, String coord, String at) {
  final deadline = DateTime.now().add(limit);
  var state = '';
  while (DateTime.now().isBefore(deadline)) {
    state = _run('entity', ['run', coord, 'fold', '--state'], at: at).trim();
    if (state == 'idle') return state;
    sleep(const Duration(milliseconds: 300));
  }
  return state;
}

String _run(String binary, List<String> arguments, {required String at}) {
  final r = Process.runSync(binary, arguments, workingDirectory: at);
  if (r.exitCode != 0) {
    fail('$binary ${arguments.join(' ')} → ${r.exitCode}\n${r.stderr}');
  }
  return r.stdout as String;
}
