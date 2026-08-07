/// The channel, built over the two seams.
///
/// Everything here is folding: an act is one call to a body and one reading of
/// its exit code, and a read is one walk of the tree the layout describes.
/// Nothing in this file retries, and nothing in it decides — the retry lives in
/// the entity's own `lib.sh`, and the only decision this application makes is
/// the membership gate, which is asked inside that loop where it means
/// something.
library;

import 'channel.dart';
import 'handle.dart';
import 'model.dart';
import 'outcome.dart';
import 'seams.dart';

/// A channel over [ChatBodies] and [ChatTree].
final class LocalChannel implements Channel {
  LocalChannel({
    required this.name,
    required ChatBodies bodies,
    required ChatTree tree,
    required Identity identity,
    String? cursor,
    int attempts = defaultAttempts,
  })  : _bodies = bodies,
        _tree = tree,
        _identity = identity,
        _cursor = cursor,
        _attempts = attempts;

  @override
  final String name;

  final ChatBodies _bodies;
  final ChatTree _tree;
  final Identity _identity;
  final int _attempts;

  String? _cursor;

  @override
  String get coordinate => '$chatOntology:$name';

  @override
  Handle get me => _identity.handle;

  @override
  String? get cursor => _cursor;

  // ── acting ─────────────────────────────────────────────────────────────────

  @override
  Future<ActResult> join({String? displayName}) => _act(
        'join',
        displayName == null ? const [] : ['--name', displayName],
      );

  @override
  Future<ActResult> say(String body) => _act('say', [body]);

  /// Walk out. The seat is torn down whole and **the transcript is not
  /// touched** — which reads as an inconsistency to whoever meets it first and
  /// is the opposite: the roster answers *who is here* and the transcript
  /// answers *what was said*, and a participant who left is absent from the
  /// first and present in the second because those are two different questions.
  /// [sync] therefore yields a [RosterChanged] and no retraction of anything.
  @override
  Future<ActResult> leave() => _act('leave', const []);

  @override
  Future<ActResult> setTopic(String text) => _act('topic', [text]);

  /// A reason of null and a reason of `''` are **the same act**: the field
  /// exists either way, because the state is the path and the reason is its
  /// contents. What the body writes for an empty reason is an empty file, which
  /// is *away, having said nothing*.
  @override
  Future<ActResult> away([String? reason]) =>
      _act('away', reason == null ? const [] : [reason]);

  @override
  Future<ActResult> back() => _act('back', const []);

  /// Runs a body and reads its exit code — **one place, so that every verb
  /// answers a lost race the same way**, and so that no verb invents a second
  /// vocabulary for what the floor already said.
  ///
  /// The bound travels down and comes back unchanged. There is no loop here:
  /// the body loops, minting the name before it so every attempt writes the
  /// same bytes at the same path, and a second loop at this altitude would
  /// multiply the bound and make [Stumbled.attempts] a lie.
  Future<ActResult> _act(String function, List<String> arguments) async {
    final outcome =
        await _bodies.run(function, arguments, attempts: _attempts);
    switch (outcome.exitCode) {
      case 0:
        return Acted(outcome.stdout.trim());
      case bodyRefused:
        // The floor's own words, never paraphrased.
        return Refused(outcome.stderr.trim());
      case bodyStumbled:
        return Stumbled(_attempts);
      default:
        throw ChatFailure(
          function,
          outcome.stderr.trim().isEmpty
              ? outcome.stdout.trim()
              : outcome.stderr.trim(),
          exitCode: outcome.exitCode,
        );
    }
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
    // An unborn channel has nothing to yield, and that is not an error: nobody
    // has opened it, and there was never anything to be behind on.
    if (_tree.tip() == null) return const [];

    final acts = _tree.log().reversed.toList();
    var from = 0;
    if (_cursor != null) {
      final seen = acts.indexWhere((a) => a.commit == _cursor);
      // A cursor this line does not carry is a cursor from somewhere else, and
      // the honest answer is the conversation whole rather than silence.
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

    _cursor = _tree.tip();
    return events;
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
