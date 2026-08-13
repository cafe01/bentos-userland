/// The channel, built over the two seams.
///
/// Reading is one walk of the tree the layout describes. Acting **opens the
/// bracket in process**: a private area, a membership gate asked of that same
/// area, a writer, a compare-and-swap — looped here, bounded by [_attempts],
/// and nowhere else. It used to live in the entity's own embarked shell body,
/// inherited by spawning a process and mapping its exit codes; that face is
/// retired, and every writer this file owns (`join`, `say`, `leave`, `topic`,
/// `away`, `back`) is what the shell's own bodies wrote, moved here whole.
library;

import 'dart:async';
import 'dart:math' as math;

import 'channel.dart';
import 'handle.dart';
import 'mention.dart';
import 'model.dart';
import 'outcome.dart';
import 'seams.dart';
import '../chat_client/ticker.dart';

/// A channel over [ChatActs], [ChatTree] and the doorbell [wait] wakes on.
final class LocalChannel implements Channel {
  LocalChannel({
    required this.name,
    required ChatActs acts,
    required ChatTree tree,
    required Identity identity,
    required Ticker Function() ticker,
    String? cursor,
    int attempts = defaultAttempts,
    DateTime Function() clock = DateTime.now,
  })  : _acts = acts,
        _tree = tree,
        _identity = identity,
        _openTicker = ticker,
        _cursor = cursor,
        _attempts = attempts,
        _clock = clock;

  @override
  final String name;

  final ChatActs _acts;
  final ChatTree _tree;
  final Identity _identity;
  final Ticker Function() _openTicker;
  final int _attempts;
  final DateTime Function() _clock;

  static const _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static final _entropy = math.Random();

  /// The burst window: fixed, opened once by the first qualifying event.
  static const Duration _settle = Duration(seconds: 1);

  String? _cursor;

  @override
  String get coordinate => '$chatOntology:$name';

  @override
  Handle get me => _identity.handle;

  @override
  String? get cursor => _cursor;

  // ── acting ─────────────────────────────────────────────────────────────────

  /// Joining is the one door in: it births the channel when it does not exist
  /// yet, since membership is what an external will enters the graph through.
  /// **Idempotent, by reading the area and never by remembering** —
  /// reconnecting is ordinary, and re-joining lands a second act saying so
  /// while leaving the roster where it already was.
  @override
  Future<ActResult> join({String? displayName}) async {
    final display = displayName ?? _identity.displayName;
    final joinedAt = _isoNow(_clock().toUtc());
    _acts.ensureBorn();
    return _act(
      'membership',
      gated: false,
      say: 'join · $me${display == null || display.isEmpty ? '' : ' ($display)'}',
      write: (area) {
        final seat = '$participantsPath/${me.local}';
        // Written once and left alone: a real return is dated afresh only by
        // way of `leave` tearing the seat down first.
        if (!area.exists('$seat/joined')) area.write('$seat/joined', '$joinedAt\n');
        if (display != null && display.isNotEmpty) area.write('$seat/name', '$display\n');
      },
    );
  }

  @override
  Future<ActResult> say(String body) async {
    final now = _clock().toUtc();
    // Minted once, before the loop, so every attempt writes the same bytes at
    // the same path and landing twice is impossible.
    final id = _ulid(now.millisecondsSinceEpoch);
    final path = '$messagesPath/${_two(now.year, 4)}/${_two(now.month)}/'
        '${_two(now.day)}/$id.md';
    final author = '${_identity.displayName ?? ''} <${me.email}>';
    final spoken = _isoNow(now);
    return _act(
      'message',
      say: 'say · $me · "${_clip(body)}"',
      write: (area) =>
          area.write(path, 'author: $author\nspoken: $spoken\n\n$body\n'),
    );
  }

  /// Walk out. The seat is torn down whole and **the transcript is not
  /// touched** — which reads as an inconsistency to whoever meets it first and
  /// is the opposite: the roster answers *who is here* and the transcript
  /// answers *what was said*, and a participant who left is absent from the
  /// first and present in the second because those are two different questions.
  /// [sync] therefore yields a [RosterChanged] and no retraction of anything.
  @override
  Future<ActResult> leave() => _act(
        'membership',
        say: 'leave · $me',
        write: (area) => area.removeTree('$participantsPath/${me.local}'),
      );

  @override
  Future<ActResult> setTopic(String text) => _act(
        'topic',
        say: 'topic · $me · "${_clip(text)}"',
        write: (area) => area.write(topicPath, '$text\n'),
      );

  /// A reason of null and a reason of `''` are **the same act**: the field
  /// exists either way, because the state is the path and the reason is its
  /// contents. What is written for an empty reason is an empty file, which is
  /// *away, having said nothing*.
  @override
  Future<ActResult> away([String? reason]) => _act(
        'presence',
        say: 'away · $me${reason == null || reason.isEmpty ? '' : ' — ${_clip(reason)}'}',
        write: (area) =>
            area.write('$participantsPath/${me.local}/away', reason ?? ''),
      );

  @override
  Future<ActResult> back() => _act(
        'presence',
        say: 'back · $me',
        write: (area) => area.removeTree('$participantsPath/${me.local}/away'),
      );

  /// Attempts one act, bounded by [_attempts] — **the loop lives here, and it
  /// lives here alone.** [gated] is asked of each attempt's own private area,
  /// never of the present tree, so a participant who joined mid-retry is seen.
  ///
  /// [ChatActs.attempt] never retries by itself: a second loop under this one
  /// would multiply the bound and make [Stumbled.attempts] a lie.
  Future<ActResult> _act(
    String noun, {
    required void Function(ChatArea area) write,
    required String say,
    bool gated = true,
  }) async {
    if (gated && !_acts.born) throw NoSuchChannel(coordinate);
    for (var attempt = 1; attempt <= _attempts; attempt++) {
      final outcome = _acts.attempt(
        noun,
        write: write,
        gate: gated ? _membershipGate : null,
        say: say,
      );
      switch (outcome) {
        case ChatLanded(:final commit):
          return Acted(commit);
        case ChatGateRefused(:final reason):
          return Refused(reason);
        case ChatContested():
          if (attempt < _attempts) await Future<void>.delayed(_backoff(attempt));
      }
    }
    return Stumbled(_attempts);
  }

  /// How long a loser waits before opening the bracket again — **full jitter**,
  /// uniform in `[0, base * 2^(n-1)]`, capped at [_backoffCap].
  ///
  /// The uniform lower bound of zero is the whole mechanism: a *flat* wait, of
  /// any width, leaves two writers that met once meeting again with the same
  /// probability, so the per-attempt loss never decays and the tail stays
  /// geometric — a bound then truncates that tail rather than removing it, which
  /// is what eight attempts were doing. Doubling the window each time spreads
  /// the writers that keep colliding over an interval that outgrows the bracket
  /// they collide inside, and the loss decays.
  ///
  /// [_backoffBase] is the order of one bracket — materialize an area, write,
  /// commit-tree, swap — since a window narrower than the act it separates
  /// cannot separate anything. **The delay is never a deadline**: the bound is
  /// [_attempts] and only [_attempts], so a slower machine retries slower and
  /// gets the same number of chances.
  static Duration _backoff(int attempt) {
    final window = _backoffBase.inMilliseconds * (1 << (attempt - 1));
    final bounded = window > _backoffCap.inMilliseconds
        ? _backoffCap.inMilliseconds
        : window;
    return Duration(milliseconds: _entropy.nextInt(bounded + 1));
  }

  /// The first window, and the order of one act bracket.
  static const Duration _backoffBase = Duration(milliseconds: 100);

  /// Where the doubling stops. Past this the window is already far wider than
  /// any bracket, and growing it only makes a losing writer slow to give up.
  static const Duration _backoffCap = Duration(seconds: 4);

  /// The one gate of this application, asked of the attempt's own area: a
  /// member is a seat, and a seat is a directory.
  String? _membershipGate(ChatArea area) {
    if (area.exists('$participantsPath/${me.local}')) return null;
    return '$chatOntology: refused — $me is not in $coordinate (join first)';
  }

  /// One reading of the clock, ISO-8601, second resolution — what every
  /// timestamp this channel writes states about itself.
  static String _isoNow(DateTime utc) => '${utc.toIso8601String().split('.').first}Z';

  static String _two(int n, [int width = 2]) => '$n'.padLeft(width, '0');

  /// A sentence's tail, for the log.
  static String _clip(String text, [int max = 60]) {
    final flat = text.replaceAll('\n', ' ');
    return flat.length > max ? flat.substring(0, max) : flat;
  }

  /// Crockford's base32 over a 48-bit millisecond timestamp and 80 bits of
  /// randomness — unique, and sorting by time as a tiebreak.
  String _ulid(int ms) {
    final time = List<String>.filled(10, '0');
    var t = ms;
    for (var i = 9; i >= 0; i--) {
      time[i] = _crockford[t % 32];
      t ~/= 32;
    }
    final random = StringBuffer();
    for (var i = 0; i < 16; i++) {
      random.write(_crockford[_entropy.nextInt(32)]);
    }
    return '${time.join()}$random';
  }

  // ── reading ────────────────────────────────────────────────────────────────

  @override
  Future<String?> topic({String? at}) async {
    _born();
    return _tree.read(topicPath, at: _resolve(at))?.trim();
  }

  @override
  Future<Roster> roster({String? at}) async {
    _born();
    return _roster(at: _resolve(at));
  }

  @override
  Future<List<Message>> history({
    DateTime? since,
    DateTime? until,
    int? limit,
    String? at,
  }) async {
    _born();
    var transcript = _transcript(_upTo(_tree.log().reversed, _resolve(at)));
    if (since != null) {
      transcript = transcript.where((m) => !m.spoken.isBefore(since)).toList();
    }
    if (until != null) {
      transcript = transcript.where((m) => !m.spoken.isAfter(until)).toList();
    }
    // The limit takes **the last to arrive**, which is the tail of the log and
    // not the tail of any clock.
    if (limit != null && transcript.length > limit) {
      transcript = transcript.sublist(transcript.length - limit);
    }
    return transcript;
  }

  @override
  Future<List<ChannelEvent>> sync() async {
    final events = _eventsSince(_cursor);
    _cursor = _tree.tip();
    return events;
  }

  /// What has landed since [cursor] — the pure read [sync] advances the
  /// cursor over, and [wait] peeks with **without ever moving it**: a wait
  /// carries no content, so whatever it sees while polling must still be
  /// there for the caller's own [sync] once it returns.
  List<ChannelEvent> _eventsSince(String? cursor) {
    // An unborn channel has nothing to yield, and that is not an error:
    // nobody has opened it, and there was never anything to be behind on.
    if (_tree.tip() == null) return const [];

    final acts = _tree.log().reversed.toList();
    var from = 0;
    if (cursor != null) {
      final seen = acts.indexWhere((a) => a.commit == cursor);
      // A cursor this line does not carry is a cursor from somewhere else,
      // and the honest answer is the conversation whole rather than silence.
      if (seen >= 0) from = seen + 1;
    }

    final events = <ChannelEvent>[];
    Roster? rosterNow;
    for (final act in acts.sublist(from)) {
      switch (act.noun) {
        case 'message':
          events.addAll(_messagesOf(act).map(Spoke.new));
        case 'membership':
        case 'presence':
          // Carried **as read at the end of the batch** rather than as a
          // difference: the roster is one listing, and folding a diff out of
          // the log is the expense the materialized layout exists to avoid.
          events.add(RosterChanged(rosterNow ??= _roster()));
        case 'topic':
          final text = _tree.read(topicPath, at: act.commit);
          if (text != null) {
            events.add(
              TopicChanged(text.trim(), Handle.ofEmail(act.authorEmail)),
            );
          }
      }
    }
    return events;
  }

  /// **The window opens on the first qualifying event and closes [_settle]
  /// later**, so a burst — several messages, a replay — comes back as one
  /// waking rather than one per line. Before it opens, [within] bounds the
  /// wait.
  ///
  /// Polling never touches the cursor: only [_eventsSince] is asked, so
  /// whatever this found is still there, entire, for the caller's own [sync]
  /// once this returns.
  @override
  Future<Arrival> wait({Duration? within, String? mentioning}) async {
    final scanner =
        mentioning == null ? null : MentionScanner(Handle(mentioning, ''));
    final ticker = _openTicker();
    final deadline = within == null ? null : DateTime.now().add(within);
    DateTime? windowCloses;

    try {
      while (true) {
        final events = _eventsSince(_cursor)
            .where((e) => e is! Spoke || e.message.author != me)
            .toList();
        final relevant = scanner == null
            ? events
            : events
                .where((e) => e is Spoke && scanner.mentions(e.message.body))
                .toList();
        if (relevant.isNotEmpty) windowCloses ??= DateTime.now().add(_settle);

        // Nothing landed yet and the doorbell itself is down: throw, rather
        // than let the wall clock alone answer and leave a stumble reading
        // the same as a channel that was simply quiet. Once a window is
        // open the burst it already caught is honored instead.
        if (windowCloses == null && !ticker.connected) {
          throw const DoorbellDown();
        }

        final now = DateTime.now();
        if (windowCloses != null && !now.isBefore(windowCloses)) {
          return Arrival.landed;
        }
        if (windowCloses == null &&
            deadline != null &&
            !now.isBefore(deadline)) {
          return Arrival.expired;
        }

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
  }

  // ── the layout, read ───────────────────────────────────────────────────────

  void _born() {
    if (_tree.tip() == null) throw NoSuchChannel(coordinate);
  }

  /// A point in history, as a caller gave it: null is the present, and anything
  /// else is **a commit of this line** — named whole or by the prefix a hand
  /// types. Resolved against the log rather than passed down raw, because a sha
  /// this line does not carry is a question about another channel, and answering
  /// it with the present would be answering a question nobody asked.
  String? _resolve(String? at) {
    if (at == null) return null;
    final matches = [
      for (final act in _tree.log())
        if (act.commit == at || act.commit.startsWith(at)) act.commit,
    ];
    if (matches.isEmpty) throw NoSuchCommit(coordinate, at);
    // An exact hit stands whatever else shares its prefix; only a genuinely
    // short-of-unique prefix is ambiguous.
    if (matches.contains(at)) return at;
    if (matches.length > 1) throw AmbiguousCommit(coordinate, at, matches);
    return matches.single;
  }

  /// The acts up to and including [at], the sequence given oldest first. The
  /// transcript as of a commit is what had landed by then and nothing after it.
  Iterable<ChatAct> _upTo(Iterable<ChatAct> acts, String? at) {
    if (at == null) return acts;
    final upTo = <ChatAct>[];
    for (final act in acts) {
      upTo.add(act);
      if (act.commit == at) break;
    }
    return upTo;
  }

  /// Who is in the channel — **one listing**, and never a walk over the log.
  Roster _roster({String? at}) {
    final participants = <Participant>[];
    for (final entry in _tree.ls(participantsPath, at: at)) {
      final local = entry.endsWith('/')
          ? entry.substring(0, entry.length - 1)
          : entry;
      // Git carries no empty folder, so the class's structure is kept by a
      // `.gitkeep` every instance inherits and nobody joined as.
      if (local.startsWith('.')) continue;
      final seat = '$participantsPath/$local';
      final joined = _tree.read('$seat/joined', at: at);
      if (joined == null) continue;
      final displayName = _tree.read('$seat/name', at: at)?.trim();
      // **Presence is asked of the path and not of the bytes**: the file exists
      // when the participant is away, and its contents are the reason. An empty
      // string is *away, having said nothing*; null is *here*.
      final away = _tree.read('$seat/away', at: at)?.trim();
      participants.add(
        Participant(
          handle: Handle(local, ''),
          joined: DateTime.parse(joined.trim()).toUtc(),
          displayName:
              displayName == null || displayName.isEmpty ? null : displayName,
          away: away,
        ),
      );
    }
    return _Roster(participants);
  }

  /// The transcript, in the order the acts are given — **arrival order**, which
  /// is the log's and never the clock's.
  List<Message> _transcript(Iterable<ChatAct> acts) {
    final transcript = <Message>[];
    for (final act in acts) {
      if (act.noun != 'message') continue;
      transcript.addAll(_messagesOf(act));
    }
    return transcript;
  }

  /// The messages one act deposited, read **at the commit that added them** —
  /// so a transcript is what was said when it was said, whatever the present
  /// tree happens to hold.
  Iterable<Message> _messagesOf(ChatAct act) sync* {
    for (final path in _tree.added(act.commit)) {
      if (!path.startsWith('$messagesPath/') || !path.endsWith('.md')) continue;
      final bytes = _tree.read(path, at: act.commit);
      if (bytes == null) continue;
      yield _message(path, bytes, act);
    }
  }

  /// A message states its own author and time although the commit carries both,
  /// so that rendering is reading files rather than plumbing per message. Where
  /// the file says nothing, the act answers — the commit is the proof, and
  /// reconciling the two is `check`'s job and not this reader's.
  Message _message(String path, String bytes, ChatAct act) {
    String? author;
    String? spoken;
    final lines = bytes.split('\n');
    var body = 0;
    for (; body < lines.length; body++) {
      final line = lines[body];
      if (line.trim().isEmpty) {
        body++;
        break;
      }
      final colon = line.indexOf(':');
      if (colon < 0) break;
      final field = line.substring(0, colon).trim();
      final value = line.substring(colon + 1).trim();
      if (field == 'author') author = value;
      if (field == 'spoken') spoken = value;
    }

    final name = path.split('/').last;
    return Message(
      id: name.substring(0, name.length - '.md'.length),
      author: Handle.ofEmail(_address(author) ?? act.authorEmail),
      spoken: spoken == null
          ? act.instant
          : (DateTime.tryParse(spoken)?.toUtc() ?? act.instant),
      body: lines.sublist(body).join('\n').trimRight(),
    );
  }

  /// `Alfred <alfred@bentos.life>` → the address. A line with no angle brackets
  /// is taken whole, which is what a body that had no display name writes.
  static String? _address(String? author) {
    if (author == null || author.isEmpty) return null;
    final open = author.lastIndexOf('<');
    final close = author.lastIndexOf('>');
    if (open < 0 || close < open) return author.trim();
    return author.substring(open + 1, close).trim();
  }
}

/// Resolves on whichever comes first: the next tick, or [duration] elapsing.
/// Neither outcome is reported back — the caller re-reads the events and the
/// wall clock itself on the next loop turn to find out which one it was.
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

final class _Roster implements Roster {
  _Roster(this._participants);

  final List<Participant> _participants;

  @override
  Iterable<Participant> get participants => _participants;

  @override
  Participant? byHandle(String local) {
    for (final participant in _participants) {
      if (participant.handle.local == local) return participant;
    }
    return null;
  }

  /// **By the local part alone**, because that is the whole of what the layout
  /// carries: a seat is a directory named by a handle, and the origin never
  /// entered the tree. The surface stores a handle whole where it has one; the
  /// roster has only half, and pretending otherwise would make membership
  /// answer no to the participant who is standing in it.
  @override
  bool contains(Handle handle) => byHandle(handle.local) != null;
}
