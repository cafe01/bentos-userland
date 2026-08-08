/// `llm session` — the shell register over the session face.
///
/// A register is a skin of I/O and nothing else: each verb here parses what was
/// typed, makes **one** call into the face, and hands what came back to the
/// printer. No verb folds, derives, retries or decides — everything worth being
/// wrong about lives one floor down, under the contract suite, or in the printer
/// and the error mapper, which are pure and have a gate of their own.
///
/// This is the scripted line. The shell as a REPL, the TUI and the window are
/// its sisters, and none of them is the official one.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../../session/construction.dart';
import '../../session/coordinate.dart';
import '../../session/entity_primitive.dart';
import '../../session/face.dart';
import '../../session/primitive.dart';
import '../../session/session.dart';
import '../../session/transcript.dart';
import '../../session/turn.dart';
import '../session/errors.dart';
import '../session/printer.dart';
import '../session/where.dart';

/// The face, over the real floor. Built once per invocation: a register holds no
/// state, so there is nothing here to keep between calls.
({SessionFace face, Primitive primitive}) _open() {
  const primitive = EntityPrimitive();
  const construction = LlmSessionConstruction();
  final machine = construction.machineOver(primitive);
  return (
    face: construction.face(
      primitive: primitive,
      coordinates: construction.coordinatesOver(primitive),
      machine: machine,
      transcripts: construction.transcriptsOver(primitive),
      view: construction.view,
      rest: construction.restOver(machine),
    ),
    primitive: primitive,
  );
}

final class SessionCommand extends Command<int> {
  SessionCommand() {
    addSessionGlobals(argParser);
    addSubcommand(SessionNewCommand());
    addSubcommand(SessionSayCommand());
    addSubcommand(SessionShowCommand());
    addSubcommand(SessionMonitorCommand());
    addSubcommand(SessionReplCommand());
  }

  @override
  String get name => 'session';

  @override
  String get description =>
      'Conversations that live in an entity: open one, speak into it, and look '
      'at it.';

  @override
  String get invocation => 'llm session [-s <session>] <verb>';
}

/// What every verb of the register shares: the coordinate, the vantage, and the
/// one place a failure becomes a sentence and a code.
abstract base class SessionSubcommand extends Command<int> {
  /// The globals are read off the `session` command's results, which is where
  /// they were declared — a verb never re-declares them.
  ArgResults? get _globals => parent?.argResults;

  Coordinate get coordinate => coordinateFrom(_globals);
  Vantage get vantage => vantageFrom(_globals);

  Lens lensOf(String? spelled) =>
      spelled == null ? Lens.conversation : Lens.values.byName(spelled);

  /// The verb's own body. Everything it throws is answered by [run].
  Future<int> act();

  @override
  Future<int> run() => reporting(act);
}

void _addLens(ArgParser parser) {
  parser.addOption(
    'lens',
    abbr: 'l',
    allowed: ['conversation', 'work', 'audit'],
    defaultsTo: 'conversation',
    allowedHelp: {
      'conversation': 'you and the agent — calls collapsed, reasoning hidden',
      'work': 'the machinery — calls, arguments, results, reasoning',
      'audit': 'the acts — sha, act, actor',
    },
  );
}

// ── opening ────────────────────────────────────────────────────────────────

final class SessionNewCommand extends SessionSubcommand {
  SessionNewCommand() {
    argParser
      ..addOption(
        'as',
        help: 'The name of the conversation.\nDefaults to a timestamp.',
      )
      ..addOption(
        'entity',
        help: 'The body the conversation runs on — anything that fuses\n'
            'the session ontology.',
      )
      ..addOption('device', help: 'The model device replies run against.')
      ..addOption(
        'system',
        help: 'The constitution: a path to read, or the text itself.\n'
            'A real constitution does not fit in argv, so a path that\n'
            'exists is read.',
      )
      ..addOption(
        'tools',
        help: 'A directory of functions to plug: <name> executable beside\n'
            '<name>.json declaring it.',
      );
  }

  @override
  String get name => 'new';

  @override
  String get description => 'Open a conversation.';

  @override
  String get invocation => 'llm session new [--as <name>]';

  @override
  Future<int> act() async {
    final opened = _open();
    final named = argResults!['as'] as String?;
    final entity = argResults!['entity'] as String?;
    final tools = argResults!['tools'] as String?;

    if (tools != null && !Directory(tools).existsSync()) {
      throw UsageException('llm session new: no such directory: $tools', usage);
    }

    // Carried from `chat new`: opening at a conversation that already stands
    // would deposit a second `user.open` into a live transcript. The face does
    // not guard it, and that is a debt of the face proper rather than of this
    // register — stated here so the guard is not mistaken for a skin's whim.
    // It can only be asked when a name was typed; a minted one is new by
    // construction.
    if (named != null) {
      final coord = Coordinate(entity ?? sessionOntology, named);
      if (await opened.primitive.tip(coord, vantage: vantage) != null) {
        stderr.writeln(
          'llm session new: ${coord.entity}:${coord.instance} already exists',
        );
        return 1;
      }
    }

    final session = await opened.face.open(
      name: named,
      entity: entity,
      device: argResults!['device'] as String?,
      // A constitution is text, and text this long lives in a file. Reading it
      // is the skin's job: file I/O is exactly what a register is for, and the
      // face takes the contents.
      system: _constitution(argResults!['system'] as String?),
      functions: tools,
      vantage: vantage,
    );

    final armed = await _armTheCircuit(session.coordinate);
    if (armed != 0) return armed;

    stdout.writeln(session.coordinate.instance);
    stderr.writeln(
      'llm session: talk to it with  llm session -s '
      '${session.coordinate.entity}:${session.coordinate.instance} repl',
    );
    return 0;
  }

  String? _constitution(String? value) {
    if (value == null) return null;
    final file = File(value);
    return file.existsSync() ? file.readAsStringSync() : value;
  }

  /// -----------------------------------------------------------------------
  /// ON LOAN — carried verbatim from `chat new`, and it dies whole.
  ///
  /// The entity declares these three landings in its own `on:` table, and
  /// `install` reading that table is what will arm them. That reading is
  /// committed on the entity primitive's front and arms at the **class**
  /// coordinate, which refuses the first act of every instance (item 1a). Until
  /// 1a lands, a conversation nobody armed is a conversation that never
  /// answers, so the register arms it — three landings, and only for the
  /// conversation it just opened, never for `*`, because a listener cannot be
  /// told which instance woke it and one armed across all of them runs every
  /// other conversation's bodies.
  ///
  /// When 1a lands: delete this function and the call above. Nothing else in
  /// the register changes.
  ///
  /// It reaches `entity` directly rather than through the face's [Primitive],
  /// which declares no arming on purpose. That reach is the loan itself, and it
  /// is why it lives in the skin and not one floor down.
  /// -----------------------------------------------------------------------
  Future<int> _armTheCircuit(Coordinate coord) async {
    const circuit = <(String, String)>[
      ('prompt.landed', 'assistant.reply'),
      ('function-result.landed', 'assistant.reply'),
      ('reply.landed', 'executor.run'),
    ];
    final spelled = '${coord.entity}:${coord.instance}';
    final place = vantage.place == null ? const <String>[] : ['-C', vantage.place!];
    for (final (event, function) in circuit) {
      final armed = await Process.run('entity', [
        ...place,
        'on',
        spelled,
        event,
        '--',
        'entity',
        ...place,
        'run',
        spelled,
        function,
      ]);
      if (armed.exitCode != 0) {
        stderr.write(armed.stderr);
        stderr.writeln(
          'llm session new: could not arm $event → $function',
        );
        return armed.exitCode;
      }
    }
    return 0;
  }
}

// ── speaking ───────────────────────────────────────────────────────────────

final class SessionSayCommand extends SessionSubcommand {
  SessionSayCommand() {
    argParser
      ..addFlag(
        'wait',
        defaultsTo: true,
        help: 'Wait for the conversation to come back to rest.\n'
            'The circuit is asynchronous: the act that deposits a prompt\n'
            'returns as soon as it has committed, and the reply lands\n'
            'seconds later. Without the wait there is nothing to print yet.',
      )
      ..addOption(
        'timeout',
        defaultsTo: '180',
        help: 'Seconds to wait for rest before giving up on the wait.',
      );
    _addLens(argParser);
  }

  @override
  String get name => 'say';

  @override
  String get description => 'Say something to the conversation.';

  @override
  String get invocation => 'llm session [-s <session>] say <text>';

  @override
  Future<int> act() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      throw UsageException('llm session say: <text> is required', usage);
    }
    final seconds = int.tryParse(argResults!['timeout'] as String);
    if (seconds == null) {
      throw UsageException('llm session say: --timeout takes seconds', usage);
    }

    final turn = await _open().face.say(
      coordinate,
      rest.single,
      wait: argResults!['wait'] as bool,
      limit: Duration(seconds: seconds),
      lens: lensOf(argResults!['lens'] as String?),
      vantage: vantage,
    );
    return _reportTurn(turn, seconds);
  }
}

/// What a turn looks like on a terminal, and what it exits with. Shared by `say`
/// and the loop, which are the same three steps.
int _reportTurn(TurnResult turn, int seconds) {
  for (final line in renderTurns(turn.landed)) {
    stdout.writeln(line);
  }
  switch (turn.outcome) {
    case TurnOutcome.rested:
      return 0;
    case TurnOutcome.timedOut:
      stderr.writeln(
        'llm session: still working after ${seconds}s — it is not lost, '
        'look again with `llm session show`',
      );
      return 1;
    case TurnOutcome.cancelled:
      stderr.writeln('-- stopped looking; the turn is still running');
      return 1;
    case TurnOutcome.refused:
      // The floor's own words, and the floor's own grade. A verdict: saying
      // it again will not help.
      stderr.writeln('llm session: refused — ${turn.refusal}');
      return refusedCode;
    case TurnOutcome.contested:
      // The floor's own words, and the floor's own grade. Not a verdict: the
      // ref moved, and reading the tip again and saying it again terminates.
      stderr.writeln('llm session: contested — ${turn.refusal}');
      return contestedCode;
  }
}

// ── seeing ─────────────────────────────────────────────────────────────────

final class SessionShowCommand extends SessionSubcommand {
  SessionShowCommand() {
    argParser.addOption(
      'as-of',
      help: 'Read the conversation at an older commit.',
      valueHelp: 'sha',
    );
    _addLens(argParser);
  }

  @override
  String get name => 'show';

  @override
  String get description => 'Show the conversation, pinned at one commit.';

  @override
  String get invocation => 'llm session [-s <session>] show [-l <lens>]';

  @override
  Future<int> act() async {
    final asOf = argResults!['as-of'] as String?;
    final screen = await _open().face.show(
      coordinate,
      lens: lensOf(argResults!['lens'] as String?),
      asOf: asOf == null ? null : Sha(asOf),
      vantage: vantage,
    );
    for (final line in renderScreen(screen)) {
      stdout.writeln(line);
    }
    return 0;
  }
}

final class SessionMonitorCommand extends SessionSubcommand {
  SessionMonitorCommand() {
    _addLens(argParser);
  }

  @override
  String get name => 'monitor';

  @override
  String get description =>
      'Watch the conversation live — the entity writes as it moves.';

  @override
  String get invocation => 'llm session [-s <session>] monitor [-l <lens>]';

  /// The live register writes to the terminal for as long as it lives, and it
  /// is the entity's own body that writes: nothing is rendered here, and the
  /// exit code is the body's.
  @override
  Future<int> act() => _open().face.monitor(
        coordinate,
        lens: lensOf(argResults!['lens'] as String?),
        vantage: vantage,
      );
}

// ── the loop ───────────────────────────────────────────────────────────────

final class SessionReplCommand extends SessionSubcommand {
  SessionReplCommand() {
    argParser.addOption(
      'timeout',
      defaultsTo: '180',
      help: 'Seconds to wait for each turn to come to rest.',
    );
  }

  @override
  String get name => 'repl';

  @override
  String get description => 'Sit in the conversation.';

  @override
  String get invocation => 'llm session [-s <session>] repl';

  /// `repl` is `show` and `say` in a loop, and it is **explicit**: a loop of our
  /// own is one register among others, and the loop that matters belongs to the
  /// shell. It is never the default verb.
  @override
  Future<int> act() async {
    final face = _open().face;
    final coord = coordinate;
    final seconds = int.tryParse(argResults!['timeout'] as String);
    if (seconds == null) {
      throw UsageException('llm session repl: --timeout takes seconds', usage);
    }
    final limit = Duration(seconds: seconds);

    // Where the conversation stands, so that sitting down is joining it rather
    // than starting in the dark.
    for (final line
        in renderTurns((await face.show(coord, vantage: vantage)).turns)) {
      stdout.writeln(line);
    }

    var interrupted = false;
    final signals =
        ProcessSignal.sigint.watch().listen((_) => interrupted = true);
    try {
      while (true) {
        stdout.write('> ');
        final line = stdin.readLineSync();
        if (line == null) {
          // Ctrl-D. The newline is ours: the terminal printed nothing.
          stdout.writeln();
          return 0;
        }
        // A signal raised while the terminal was blocking here belongs to no
        // turn: it is dropped rather than cancelling the turn about to start.
        interrupted = false;
        if (line.trim().isEmpty) continue;

        final turn = await face.say(
          coord,
          line,
          limit: limit,
          cancelled: () => interrupted,
          vantage: vantage,
        );
        _reportTurn(turn, seconds);
      }
    } finally {
      await signals.cancel();
    }
  }
}
