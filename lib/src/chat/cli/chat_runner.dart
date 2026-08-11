/// The `bentos.chat` coreutil — the shell's face on a channel.
///
/// **A face, and not the contract.** It adds nothing to the API and states
/// nothing the medium does not already hold: every verb here is one call to
/// [Channel] and one rendering of what came back. The command is the entity's
/// own name, so one namespace serves identity, repository and PATH entry and no
/// collision forms as entities are installed.
///
/// There is **no seat in the line**, because the ontology has one and the caller
/// is it: `bentos.chat say` is the whole clause, and who spoke is the author git
/// puts on the commit — a person at a keyboard and a program in a pipe enter by
/// the same door and are told apart afterwards rather than beforehand.
///
/// There is **no `arm` and no `disarm`**. Nothing in this entity reacts, so
/// there is nothing for the face to register: a client that wants to wake on
/// speech arms its own executable with the generic `entity on` at the channel's
/// coordinate, and the medium is not involved and does not record it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

// Only the absence: the face stands on the floor's own vocabulary for a thing
// that is not installed, and translates nothing else of the primitive's.
import '../../entity/entity.dart' show EntityNotInstalled;
import '../../chat_client/ticker.dart';
import '../channel.dart';
import '../handle.dart';
import '../mention.dart';
import '../outcome.dart';
import '../seams.dart';
import 'coordinate.dart';
import 'floor.dart';
import 'monitor_cursor.dart';
import 'render.dart';

/// The runner behind `bin/bentos.chat.dart`.
final class ChatRunner {
  ChatRunner({
    StringSink? out,
    StringSink? err,
    String? currentDirectory,
    Map<String, String>? environment,
    Future<String> Function()? readStdin,
    this.floor = const EntityFloor(),
    io.File? monitorCursorFile,
  })  : out = out ?? io.stdout,
        err = err ?? io.stderr,
        _cwdOverride = currentDirectory,
        _envOverride = environment,
        _readStdin = readStdin ?? _stdin,
        _monitorCursorFileOverride = monitorCursorFile {
    _runner = CommandRunner<void>(
      'bentos.chat',
      'A conversation between participants: join it, speak into it, leave it.',
    )
      ..argParser.addOption(
        'place',
        abbr: 'C',
        help: 'The vantage the channel resolves from.',
        valueHelp: 'place',
      )
      ..argParser.addOption(
        'channel',
        abbr: 'c',
        help: 'Which channel. Ambient otherwise: $channelVariable, then the '
            'place, when it carries exactly one.',
        valueHelp: 'coord',
      )
      ..addCommand(_Join(this))
      ..addCommand(_Leave(this))
      ..addCommand(_Say(this))
      ..addCommand(_Topic(this))
      ..addCommand(_Away(this))
      ..addCommand(_Back(this))
      ..addCommand(_Roster(this))
      ..addCommand(_History(this))
      ..addCommand(_Monitor(this))
      ..addCommand(_Check(this))
      ..addCommand(_Where(this));
  }

  final StringSink out;
  final StringSink err;
  final ChatFloor floor;
  final String? _cwdOverride;
  final Map<String, String>? _envOverride;
  final Future<String> Function() _readStdin;
  final io.File? _monitorCursorFileOverride;

  late final CommandRunner<void> _runner;

  /// The process's answer.
  ///
  /// **0 acted · 1 not found · 3 refused · 6 timed out · 64 usage · 75
  /// stumbled.**
  ///
  /// `75` is not decoration: a stumble is *not* a refusal — nobody decided
  /// anything, the channel is simply moving faster than this writer can land
  /// in it — and the body already exits 75 for it. Flattening the two here
  /// would destroy the distinction at the exact boundary where a script reads
  /// it, and would make a busy channel indistinguishable from a hostile one.
  ///
  /// `6` belongs to `monitor --wait --timeout`, and it is a **different**
  /// nothing-happened than a stumble: 75 says a writer collided and lost, 6
  /// says a watcher waited and nothing landed at all. 75 was already spoken
  /// for by the write path, so this reuses no number and invents one instead —
  /// what must never happen either way is a caller having to parse output to
  /// tell *landed* from *timed out*.
  int exitCode = 0;

  static const int okCode = 0;
  static const int notFoundCode = 1;
  static const int refusedCode = 3;
  static const int timedOutCode = 6;
  static const int usageCode = 64;
  static const int stumbledCode = bodyStumbled;

  String get cwd => _cwdOverride ?? io.Directory.current.path;

  Map<String, String> get env => _envOverride ?? io.Platform.environment;

  /// Where `monitor --wait` persists what it has drained, per channel — never
  /// the client's read mark, which is a different question kept in a
  /// different file. Overridable so a gate can prove the cross-process cursor
  /// without touching a real `$HOME`.
  io.File get monitorCursorFile =>
      _monitorCursorFileOverride ?? MonitorCursors.defaultFile(environment: env);

  /// The vantage a channel resolves from: `-C` when given, else the working
  /// directory. Relative paths resolve against [cwd] and never the process's.
  String vantage(String? placeArg) {
    final target = placeArg ?? cwd;
    return p.normalize(p.isAbsolute(target) ? target : p.join(cwd, target));
  }

  /// Which channel, by the precedence: **argument, then variable, then the
  /// place**.
  ChatCoordinate coordinate(String? channelArg, {String? place}) {
    if (channelArg != null) {
      return ChatCoordinate(
        ChatCoordinate.parse(channelArg),
        CoordinateSource.argument,
      );
    }
    final ambient = env[channelVariable];
    if (ambient != null && ambient.trim().isNotEmpty) {
      return ChatCoordinate(
        ChatCoordinate.parse(ambient.trim()),
        CoordinateSource.environment,
      );
    }
    final anchor = vantage(place);
    final here = floor.channels(anchor);
    // One is the answer; anything else is the place declining to answer, and
    // guessing for the caller would be inventing an intention.
    if (here.length == 1) {
      return ChatCoordinate(here.single, CoordinateSource.place);
    }
    throw NoAmbientChannel(anchor, here);
  }

  /// An act's outcome, as a line and a number.
  ///
  /// A method of the runner and not an extension on it: `dart:io` exports a
  /// top-level `exitCode` setter, which an unqualified assignment inside an
  /// extension binds to in preference to this field — the number then lands on
  /// the process while the caller reads zero, and nothing says so.
  void report(ActResult result) {
    switch (result) {
      case Acted(:final commit):
        if (commit.isNotEmpty) out.writeln(commit);
      case Refused(:final reason):
        // The floor's own words, never paraphrased.
        err.writeln(reason.isEmpty ? '$chatOntology: refused' : reason);
        exitCode = refusedCode;
      case Stumbled(:final attempts):
        err.writeln(
          '$chatOntology: the channel is moving faster than this writer — '
          'the swap lost its race $attempts times. Nobody refused anything; '
          'try again.',
        );
        exitCode = stumbledCode;
    }
  }

  Future<void> run(List<String> args) async {
    try {
      await _runner.run(args);
    } on UsageException catch (e) {
      err.writeln(e.message);
      exitCode = usageCode;
    } on MalformedCoordinate catch (e) {
      err.writeln('$e');
      exitCode = usageCode;
    } on NoAmbientChannel catch (e) {
      err.writeln('$e');
      // Nothing here is absence; several is a question only the caller can
      // answer, and a question is a usage problem rather than a missing thing.
      exitCode = e.candidates.isEmpty ? notFoundCode : usageCode;
    } on AmbiguousCommit catch (e) {
      err.writeln('$e');
      exitCode = usageCode;
    } on NoSuchCommit catch (e) {
      err.writeln('$e');
      exitCode = notFoundCode;
    } on NoSuchChannel catch (e) {
      err.writeln('$e');
      exitCode = notFoundCode;
    } on EntityNotInstalled catch (e) {
      // The ordinary answer to standing outside the installation's scope, and
      // it arrived here as a stack trace and exit 255 the first time anybody
      // typed a verb from a directory with no `bentos.chat` above it. Absence
      // of the medium is absence, not a crash — and the floor already says so
      // in one sentence.
      err.writeln('$chatOntology: $e');
      exitCode = notFoundCode;
    } on NoIdentity catch (e) {
      err.writeln('$e');
      exitCode = notFoundCode;
    } on ChatFailure catch (e) {
      // **A coreutil never exits by stack trace.** The body's own words and its
      // own number: whoever wrote that program knows what its codes mean, and
      // inventing one here would discard the only report the failure made.
      err.writeln('$e');
      exitCode = e.exitCode;
    } on io.ProcessException catch (e) {
      err.writeln('$chatOntology: ${e.message.trim()}');
      exitCode = notFoundCode;
    } on StateError catch (e) {
      // What the primitive raises for the absence of a thing the caller named.
      err.writeln('$chatOntology: ${e.message}');
      exitCode = notFoundCode;
    }
  }

  static Future<String> _stdin() =>
      io.stdin.transform(utf8.decoder).join();
}

/// What every verb here shares: the two globals, and the channel they name.
abstract base class _ChatCommand extends Command<void> {
  _ChatCommand(this.face);

  /// The face this verb belongs to. Named `face` and not `runner` because
  /// `Command.runner` already exists and hands back the `CommandRunner`: a field
  /// of another type there is not a shadow, it is an invalid override, and the
  /// analyzer says so.
  final ChatRunner face;

  String? get _place => globalResults?['place'] as String?;
  String? get _channel => globalResults?['channel'] as String?;

  ChatCoordinate get coordinate =>
      face.coordinate(_channel, place: _place);

  Channel channel({String? cursor}) => face.floor.channel(
        coordinate.name,
        place: face.vantage(_place),
        cursor: cursor,
      );

  /// The single argument a verb takes, or the whole of stdin when it takes
  /// none — **which is what makes speaking from a pipe ordinary rather than
  /// special**.
  Future<String> textOrStdin() async {
    final rest = argResults!.rest;
    if (rest.length > 1) usageException('$name: one text, or none and a pipe');
    if (rest.length == 1) return rest.single;
    return (await face._readStdin()).trimRight();
  }

  /// A moment, ISO-8601 and nothing else. The rejection teaches: a face that
  /// merely refused would leave the caller guessing at a syntax nobody wrote
  /// down.
  DateTime? instant(String flag) {
    final given = argResults![flag] as String?;
    if (given == null) return null;
    final parsed = DateTime.tryParse(given);
    if (parsed == null) {
      usageException(
        "$name: --$flag takes an ISO-8601 moment (2026-08-06, "
        "2026-08-06T12:00:00Z), not '$given'",
      );
    }
    return parsed.toUtc();
  }

  /// The point in history a read answers at: a commit of this line, or the
  /// prefix of one.
  String? get asOf => argResults!['as-of'] as String?;

  void addAsOf() => argParser.addOption(
        'as-of',
        help: 'Read at a commit of this channel — the present otherwise.',
        valueHelp: 'sha',
      );
}

// ── acting ───────────────────────────────────────────────────────────────────

final class _Join extends _ChatCommand {
  _Join(super.face) {
    argParser.addOption(
      'name',
      help: 'The display name to enter under.',
      valueHelp: 'display',
    );
  }

  @override
  String get name => 'join';

  @override
  String get description =>
      'Enter the channel. Idempotent, and it opens one that is not there yet.';

  @override
  Future<void> run() async => face.report(
        await channel().join(displayName: argResults!['name'] as String?),
      );
}

final class _Leave extends _ChatCommand {
  _Leave(super.face);

  @override
  String get name => 'leave';

  @override
  String get description => 'Walk out. What was said stays said.';

  @override
  Future<void> run() async => face.report(await channel().leave());
}

final class _Say extends _ChatCommand {
  _Say(super.face);

  @override
  String get name => 'say';

  @override
  String get description => 'Speak. The text, or stdin when there is none.';

  @override
  String get invocation => 'bentos.chat say [<text>]';

  @override
  Future<void> run() async {
    final body = await textOrStdin();
    if (body.isEmpty) usageException('say: nothing to say');
    face.report(await channel().say(body));
  }
}

final class _Topic extends _ChatCommand {
  _Topic(super.face);

  @override
  String get name => 'topic';

  @override
  String get description =>
      'Set the topic, or print it when given no text. Its history is the log '
      'of that one file.';

  @override
  String get invocation => 'bentos.chat topic [<text>]';

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    // Reading is what a bare `topic` means at a keyboard, and it is the one
    // verb of this face that both reads and writes — the noun and the verb
    // being the same word in English is a fact about the language, not a
    // second surface.
    if (rest.isEmpty) {
      final topic = await channel().topic();
      if (topic != null) face.out.writeln(topic);
      return;
    }
    if (rest.length > 1) usageException('topic: one text');
    face.report(await channel().setTopic(rest.single));
  }
}

final class _Away extends _ChatCommand {
  _Away(super.face);

  @override
  String get name => 'away';

  @override
  String get description =>
      'Declare yourself away, with an optional reason. Presence is declared or '
      'absent, never simulated.';

  @override
  String get invocation => 'bentos.chat away [<reason>]';

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.length > 1) usageException('away: one reason, or none');
    face.report(
      await channel().away(rest.isEmpty ? null : rest.single),
    );
  }
}

final class _Back extends _ChatCommand {
  _Back(super.face);

  @override
  String get name => 'back';

  @override
  String get description => 'Declare yourself back.';

  @override
  Future<void> run() async => face.report(await channel().back());
}

// ── reading ──────────────────────────────────────────────────────────────────

final class _Roster extends _ChatCommand {
  _Roster(super.face) {
    addAsOf();
  }

  @override
  String get name => 'roster';

  @override
  String get description => 'Who is here — one listing, never a walk.';

  @override
  Future<void> run() async {
    final roster = await channel().roster(at: asOf);
    for (final participant in roster.participants) {
      face.out.writeln(rosterLine(participant));
    }
  }
}

final class _History extends _ChatCommand {
  _History(super.face) {
    argParser
      ..addOption(
        'since',
        help: 'Spoken at or after this ISO-8601 moment.',
        valueHelp: 'when',
      )
      ..addOption(
        'until',
        help: 'Spoken at or before this ISO-8601 moment.',
        valueHelp: 'when',
      )
      ..addOption(
        'limit',
        abbr: 'n',
        help: 'The last N to arrive — arrival, never the clock.',
        valueHelp: 'n',
      );
    addAsOf();
  }

  @override
  String get name => 'history';

  @override
  String get description =>
      'The transcript, in the order it arrived. --since and --until filter on '
      'the time a message states it was spoken.';

  @override
  Future<void> run() async {
    final transcript = await channel().history(
      since: instant('since'),
      until: instant('until'),
      limit: _limit,
      at: asOf,
    );
    for (final message in transcript) {
      face.out.writeln(messageLine(message));
    }
  }

  int? get _limit {
    final given = argResults!['limit'] as String?;
    if (given == null) return null;
    final n = int.tryParse(given);
    if (n == null || n < 0) {
      usageException("history: --limit takes a count, not '$given'");
    }
    return n;
  }
}

final class _Monitor extends _ChatCommand {
  _Monitor(super.face) {
    argParser
      ..addOption(
        'history',
        help: 'Print the last N utterances before watching.',
        valueHelp: 'n',
      )
      ..addOption(
        'interval',
        help: 'Deprecated, and warns if given: the watch wakes on dispatch '
            'now, not on a cadence, so this paces nothing.',
        valueHelp: 'seconds',
        defaultsTo: '2',
      )
      ..addFlag(
        'once',
        help: 'Drain what has landed and exit, instead of blocking.',
        negatable: false,
      )
      ..addFlag(
        'wait',
        help: 'The agent path: block for the next qualifying batch, print '
            'it, exit. A cursor is persisted per channel so the next call '
            'picks up where this one left off, across processes.',
        negatable: false,
      )
      ..addOption(
        'timeout',
        help: 'Give up after this many seconds of nothing landing — only '
            'with --wait. Exits ${ChatRunner.timedOutCode} rather than 0, so '
            'landed and timed-out are never told apart by parsing output.',
        valueHelp: 'seconds',
      )
      ..addFlag(
        'mention',
        help: 'Only wake on speech naming me, or naming everyone — a '
            'predicate over the same stream, nothing routed by the medium.',
        negatable: false,
      );
  }

  @override
  String get name => 'monitor';

  @override
  String get description =>
      'Watch the channel. Blocks, and prints what lands.';

  @override
  Future<void> run() async {
    final wait = argResults!['wait'] as bool;
    final timeout = _timeout;
    if (timeout != null && !wait) {
      usageException('monitor: --timeout only applies with --wait');
    }
    if (wait) return _runWait(timeout: timeout);

    final channel = this.channel();
    final scanner = _mentionScanner(channel);

    // Validated even though nothing below paces on it — see [_maybeWarnInterval].
    _interval;
    _maybeWarnInterval();

    if (_backlog != null) {
      for (final message in await channel.history(limit: _backlog)) {
        if (scanner == null || scanner.mentions(message.body)) {
          face.out.writeln(messageLine(message));
        }
      }
    }
    // The backlog is printed, so what has already landed must not arrive a
    // second time as an event: the cursor is wound to the tip before watching.
    await channel.sync();

    if (argResults!['once'] as bool) return;

    // **The doorbell, not the clock.** One tick means *look again* — a burst
    // of dispatch already coalesced by [ChatFloor.dispatchTicker] — and this
    // loop only ever re-reads the tree it already trusts, exactly as a poll
    // did, just woken instead of asking.
    final ticker = face.floor.dispatchTicker(face.vantage(_place));
    bool? lastConnected;
    try {
      await for (final _ in ticker.ticks) {
        lastConnected = _reportConnection(face.err, ticker, lastConnected);
        for (final event in await channel.sync()) {
          if (scanner == null || _mentioned(event, scanner)) {
            face.out.writeln(eventLine(event));
          }
        }
      }
    } finally {
      ticker.dispose();
    }
  }

  /// The agent path. **The window opens on the first qualifying event and
  /// closes [_settle] later**; everything that lands while it is open — not
  /// only what matched — returns together, so a burst comes back as one
  /// waking rather than one per line. Before that window opens, [timeout]
  /// bounds the wait; nothing landing in time exits [ChatRunner.timedOutCode]
  /// rather than 0.
  Future<void> _runWait({required Duration? timeout}) async {
    // Validated even though nothing below paces on it — see [_maybeWarnInterval].
    _interval;
    _maybeWarnInterval();

    final key = coordinate.whole;
    final cursors = MonitorCursors.load(file: face.monitorCursorFile);
    final resuming = cursors.of(key);
    final channel = this.channel(cursor: resuming);
    final scanner = _mentionScanner(channel);
    final ticker = face.floor.dispatchTicker(face.vantage(_place));

    void persist() {
      final at = channel.cursor;
      if (at != null) cursors.cursors[key] = at;
      cursors.save(file: face.monitorCursorFile);
    }

    // No special first-call priming: a channel opened at no cursor sees the
    // conversation whole, per `Channel.sync`'s own contract, so the very
    // first `--wait` for a coordinate reports everything said so far as the
    // batch — exactly as if it had been watching the whole time. Every call
    // after that persists where it left off, so nothing here is reported
    // twice.
    final deadline = timeout == null ? null : DateTime.now().add(timeout);
    final batch = <ChannelEvent>[];
    DateTime? windowCloses;
    bool? lastConnected;

    try {
      while (true) {
        lastConnected = _reportConnection(face.err, ticker, lastConnected);

        final events = await channel.sync();
        final relevant =
            scanner == null ? events : events.where((e) => _mentioned(e, scanner)).toList();
        if (relevant.isNotEmpty) {
          batch.addAll(relevant);
          windowCloses ??= DateTime.now().add(_settle);
        }
        persist();

        final now = DateTime.now();
        if (windowCloses != null && !now.isBefore(windowCloses)) break;
        if (windowCloses == null && deadline != null && !now.isBefore(deadline)) {
          face.err.writeln(
            '$chatOntology: monitor --wait timed out — nothing landed in '
            '${timeout!.inSeconds}s',
          );
          face.exitCode = ChatRunner.timedOutCode;
          return;
        }

        // Wait for whichever comes first: the next dispatch tick, or the
        // nearer of the two deadlines in play — the burst window closing,
        // the overall timeout expiring. A deadline fires off the wall clock
        // regardless of the ticker's own health, so `--timeout` stays
        // honest even while the doorbell is down.
        final nextDeadline = windowCloses ?? deadline;
        if (nextDeadline == null) {
          await ticker.ticks.first;
        } else {
          final remaining = nextDeadline.difference(DateTime.now());
          if (remaining > Duration.zero) {
            await _awaitTickOrDuration(ticker.ticks, remaining);
          }
        }
      }
    } finally {
      ticker.dispose();
    }

    for (final event in batch) {
      face.out.writeln(eventLine(event));
    }
  }

  MentionScanner? _mentionScanner(Channel channel) =>
      (argResults!['mention'] as bool) ? MentionScanner(channel.me) : null;

  bool _mentioned(ChannelEvent event, MentionScanner scanner) =>
      event is Spoke && scanner.mentions(event.message.body);

  int? get _backlog {
    final given = argResults!['history'] as String?;
    if (given == null) return null;
    final n = int.tryParse(given);
    if (n == null || n < 0) {
      usageException("monitor: --history takes a count, not '$given'");
    }
    return n;
  }

  Duration get _interval {
    final given = argResults!['interval'] as String;
    final seconds = double.tryParse(given);
    if (seconds == null || seconds <= 0) {
      usageException("monitor: --interval takes seconds, not '$given'");
    }
    return Duration(microseconds: (seconds * 1000000).round());
  }

  Duration? get _timeout {
    final given = argResults!['timeout'] as String?;
    if (given == null) return null;
    final seconds = double.tryParse(given);
    if (seconds == null || seconds <= 0) {
      usageException("monitor: --timeout takes seconds, not '$given'");
    }
    return Duration(microseconds: (seconds * 1000000).round());
  }

  /// **Deprecated, and said so out loud.** Both watch loops now wake on
  /// [ChatFloor.dispatchTicker] rather than a cadence, so a value here paces
  /// nothing — a flag that still validated silently would be a surface
  /// lying about what it does. Kept parseable, never repurposed: the same
  /// name meaning something else under the caller's feet is worse than a
  /// flag that plainly does nothing anymore.
  void _maybeWarnInterval() {
    if (argResults!.wasParsed('interval')) {
      face.err.writeln(
        '$chatOntology: monitor: --interval no longer paces anything — the '
        'medium wakes this monitor rather than being asked. Slated for '
        'removal.',
      );
    }
  }

  /// The burst window: fixed, opened once by the first qualifying event.
  static const Duration _settle = Duration(seconds: 1);
}

/// Prints the doorbell's own health flipping, on stderr and only on a real
/// change — an agent watching stdout for the delta needs a way to tell *I
/// have gone deaf* from *nothing has landed*, and those call for opposite
/// responses. Returns the connection state observed, for the caller to carry
/// as `previous` on the next call.
bool? _reportConnection(StringSink err, Ticker ticker, bool? previous) {
  final now = ticker.connected;
  if (previous != null && previous != now) {
    err.writeln(
      now
          ? '$chatOntology: monitor: dispatch reconnected'
          : '$chatOntology: monitor: dispatch disconnected — retrying',
    );
  }
  return now;
}

/// Resolves on whichever comes first: the next tick, or [duration] elapsing.
/// Neither outcome is reported back — the caller re-reads [Channel.sync] and
/// the wall clock itself on the next loop turn to find out which one it was.
Future<void> _awaitTickOrDuration(Stream<void> ticks, Duration duration) async {
  final completer = Completer<void>();
  final timer = Timer(duration, () {
    if (!completer.isCompleted) completer.complete();
  });
  final sub = ticks.listen((_) {
    if (!completer.isCompleted) completer.complete();
  });
  await completer.future;
  timer.cancel();
  await sub.cancel();
}

final class _Check extends _ChatCommand {
  _Check(super.face);

  @override
  String get name => 'check';

  @override
  String get description =>
      'The gate: a message\'s declared author is the author who signed the '
      'commit. It deposits nothing and refuses by exiting 3.';

  @override
  Future<void> run() async {
    // Not a `Channel` method, and this is the one verb of the face that says
    // so: a gate carries no seat and answers nobody. It is the entity's own
    // function, run through the primitive like any other body.
    final coordinate = this.coordinate;
    final outcome = await face.floor
        .bodies(coordinate.name, place: face.vantage(_place))
        .run('check', const [], attempts: defaultAttempts);
    if (outcome.stdout.trim().isNotEmpty) {
      face.out.writeln(outcome.stdout.trimRight());
    }
    if (outcome.stderr.trim().isNotEmpty) {
      face.err.writeln(outcome.stderr.trimRight());
    }
    face.exitCode = outcome.exitCode;
  }
}

final class _Where extends _ChatCommand {
  _Where(super.face);

  @override
  String get name => 'where';

  @override
  String get description =>
      'Which channel this shell is in, and which step named it.';

  @override
  Future<void> run() async {
    // The ambient coordinate is a precedence, and a precedence that cannot be
    // interrogated is a place to get lost in: a person surprised by which
    // channel they are speaking into needs to see which step answered.
    final coordinate = this.coordinate;
    face.out.writeln('${coordinate.whole}\t${coordinate.source.label}');
  }
}
