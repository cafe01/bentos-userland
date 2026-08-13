/// Two real writers racing over the real floor — and then four.
///
/// The gate beside it, `channel_material_test.dart`, is real in every material
/// and **sequential in every act**: it awaits each one before beginning the
/// next, and its two-actor test varies identity alone. Nothing in this suite
/// had ever put two writers at one reference at one instant, which is the
/// population R1.5, R1.14 and the channel's retry bound all quantify over.
/// [storm.dart](storm.dart) says why that witness must be processes.
///
/// **It fails when the pieces are absent; it never skips**, on the same terms
/// as the gate beside it.
///
///     dart test -t material test/chat/material/storm_material_test.dart
///
@Tags(['material'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:bentos_userland/bentos_chat.dart';
import 'package:bentos_userland/entity.dart' show Entity;
import 'package:test/test.dart';

import 'storm.dart';

/// Where the entity's genesis is — the same variable the gate beside this one
/// reads, so one clone answers for both.
String get chatSource =>
    Platform.environment['BENTOS_CHAT_SOURCE'] ?? '../../bentos.chat';

/// How long the writers are given to exist before the barrier opens. It covers
/// process start and the compile of the writer script; it is not a stagger, and
/// nothing about the storm depends on its value beyond every writer being alive
/// when the instant arrives — which [StormVerdict.overlapObserved] then checks
/// rather than assumes.
const Duration preflight = Duration(seconds: 12);

/// The bound the **setup** gets, where the setup is the join and the claim is
/// the speech. It is deliberately far above the product's own default: the
/// falsifier lesson cuts both ways, and a gate whose setup collapses reports a
/// red about the setup. Whether the product's default bound is enough for four
/// beings joining at once is a claim of its own, and it has its own gate below.
const int _generous = 64;

void main() {
  late Directory plot;

  setUpAll(() {
    _demand('entity', 'the primitive is not on PATH');
    _demand('place', 'the place organ is not on PATH');
    expect(
      Directory(chatSource).existsSync(),
      isTrue,
      reason: 'no bentos.chat genesis at $chatSource — clone it, or point '
          r'$BENTOS_CHAT_SOURCE at one. This gate does not skip.',
    );
  });

  setUp(() {
    plot = Directory.systemTemp.createTempSync('chat-storm-');
    _run('place', ['init', '-n', 'storm-gate'], at: plot.path);
    _run('entity', ['install', Directory(chatSource).absolute.path],
        at: plot.path);
  });

  tearDown(() => plot.deleteSync(recursive: true));

  /// Raises the storm and judges what it left behind.
  Future<StormVerdict> storm({
    required String channel,
    int writers = 4,
    int lines = 6,
    int attempts = defaultAttempts,
    int joinAttempts = _generous,
    Duration settle = const Duration(seconds: 4),
    bool birthFirst = true,
  }) async {
    // The channel is born before the storm, by a founder who then says
    // nothing. **Not a convenience — a separation of claims.** Birth and
    // speech are two different races, and the birth race has a defect of its
    // own (see the gate below); folding them together would let one failure
    // answer for both and leave the speech claims untested behind it.
    if (birthFirst) {
      await _read(channel, at: plot.path, as: 'Founder <founder@storm.test>')
          .join(displayName: 'Founder');
    }

    final startAt = DateTime.now().toUtc().add(preflight);
    final plans = [
      for (var i = 0; i < writers; i++)
        WriterPlan(
          writer: 'w$i',
          place: plot.path,
          channel: channel,
          identity: 'Writer $i <w$i@storm.test>',
          lines: lines,
          startAt: startAt,
          speakAt: startAt.add(settle),
          attempts: attempts,
          joinAttempts: joinAttempts,
        ),
    ];

    final reports = await stormOf(plans);
    final repository = _run('entity', ['path', 'bentos.chat'], at: plot.path).trim();
    final verdict = await judge(
      reports: reports,
      channel: _read(channel, at: plot.path),
      repository: repository,
      ref: channel,
    );
    // Printed on every run, whatever the colour: what happened and whether it
    // raced are one reading, and a gate that reports only the colour hides the
    // half that says the colour is worth anything.
    printOnFailure(verdict.describe());
    print(verdict.describe());
    return verdict;
  }

  test('four writers speaking at one instant: every line lands, once, under '
      'its own author, and the line never forks', () async {
    const lines = 6;
    const writers = 4;
    final verdict = await storm(channel: 'fabrica', writers: writers, lines: lines);

    // Whether the storm was a storm. Asked FIRST, and separately from the
    // results: a run in which the writers never overlapped, or never met at
    // the reference, is a run that proves nothing about simultaneity — and it
    // must say so rather than pass on a green transcript it obtained by
    // accidental serialization.
    expect(
      verdict.overlapObserved,
      isTrue,
      reason: 'the writers never spoke at the same time — this run did not '
          'race, and its transcript says nothing about simultaneous speech.\n'
          '${verdict.describe()}',
    );
    expect(
      verdict.contentionObserved,
      isTrue,
      reason: 'no act ever found the reference moved under it — the writers '
          'overlapped in time but never met at the reference, so this run did '
          'not exercise the retry bound.\n${verdict.describe()}',
    );

    // R1.15 — a writer can read back exactly what it landed.
    expect(verdict.missing, isEmpty,
        reason: 'a lost update: claimed landed, absent from the transcript');
    expect(verdict.duplicated, isEmpty);
    // R1.3 — each line under its own author, with four real signers.
    expect(verdict.misattributed, isEmpty);
    // R1.14 — nobody is refused; a member speaking is never gated. A stumble
    // is a legitimate outcome under this specification and is therefore not
    // asserted here: whether the shipped bound is *adequate* is a separate
    // claim, with a gate of its own below.
    expect(verdict.refused, isEmpty);
    expect(verdict.threw, isEmpty);
    expect(verdict.faults, isEmpty);
    // R1.5 — no human is ever handed a conflict. Asked of the line's shape,
    // through git, because the library has no word for a merge commit.
    expect(verdict.mergeCommits, isEmpty);
    expect(verdict.residue, isEmpty);
    // Concurrent joins, which is the same requirement's other half.
    expect(verdict.rosterAbsent, isEmpty);

    // R1.4 — one order, and it holds every landed line exactly once.
    expect(verdict.transcriptKeys.length, verdict.landed.length);
    expect(verdict.transcriptKeys.toSet().length, verdict.landed.length);
  });

  test('everything a writer said reaches the room, at the bound the product '
      'actually ships', () async {
    // **Was a declared red — intermittent and load-dependent; cured
    // 12/08/2026.** The gate above proves the medium is *correct* under a real
    // four-way race: nothing lost that claimed to land, nothing duplicated,
    // nothing misattributed, one linear order, no merge, no residue. This one
    // asks the other question — is the shipped bound enough for four beings
    // talking at once — and at eight attempts the answer was no: roughly one
    // line in eight stumbled under load, and a stumbled line is simply never
    // said. Nothing in the specification was violated, which is what made it
    // invisible from inside R1.14: the stumble was honest. What failed was §8.
    //
    // The cure is two pieces, both in the medium. `LocalChannel._act` now
    // waits **full jitter** — uniform in `[0, 100ms · 2^(n-1)]`, capped — where
    // it used to sleep a flat 100–300 ms; a flat wait of any width leaves two
    // writers that met once meeting again with the same probability, so the
    // tail stayed geometric and any bound merely truncated it. And
    // `defaultAttempts` is now **read off the measured demand** rather than
    // guessed: with the bound set to 64 under load, eight storms of 224 acts
    // all landed, peaking per storm at 7 to 11 attempts — so eight sat below
    // the observed worst case. See its doc for the measurement.
    //
    // Proven under load, which is the only condition that ever showed the red:
    // the whole material suite running its files at once, green in every run.
    const lines = 6;
    const writers = 4;
    final verdict = await storm(channel: 'lotada', writers: writers, lines: lines);

    expect(verdict.contentionObserved, isTrue,
        reason: 'nothing contended, so this run measures nothing');
    expect(
      verdict.stumbled,
      isEmpty,
      reason: 'a stumbled line is a line nobody ever hears, and the speaker '
          'is told only that the room was too fast for it',
    );
    expect(verdict.transcriptKeys.length, writers * lines);
  });

  test('the falsifier: with the bound removed the same storm loses lines, and '
      'loses exactly the ones that stumbled', () async {
    const lines = 6;
    const writers = 4;
    // One attempt is no retry at all: an act that finds the reference moved
    // has nothing left to do but stumble. Everything else about the run is
    // identical, so the two runs differ in the bound and in nothing else.
    final verdict = await storm(
      channel: 'fabrica',
      writers: writers,
      lines: lines,
      attempts: 1,
    );

    expect(
      verdict.contentionObserved,
      isTrue,
      reason: 'nothing contended, so the falsifier never reached the claim: a '
          'green here would be the storm failing to storm, not the bound '
          'being unnecessary.\n${verdict.describe()}',
    );
    expect(
      verdict.stumbled,
      isNotEmpty,
      reason: 'with no retry, a contested act must stumble — and this run '
          'contended.\n${verdict.describe()}',
    );
    // The loss is exactly the stumbles: the shortfall in the transcript is
    // accounted for line by line, so this red is the bound's absence and not
    // some incidental failure that also happens to be red.
    final spoken = verdict.stumbled
        .where((entry) => entry.startsWith('storm/'))
        .length;
    expect(spoken, greaterThan(0),
        reason: 'the stumbles must be speech: a stumbled join would refuse '
            'every line behind it, and this red would be the setup collapsing '
            'rather than the bound being what carried the claim');
    expect(
      verdict.refused,
      isEmpty,
      reason: 'nothing was refused — the loss is the missing retry and not a '
          'gate, which is what makes this red the claim\'s own',
    );
    expect(verdict.transcriptKeys.length, writers * lines - spoken);
    // And what did land is still sound: nothing lost that claimed to land,
    // nothing duplicated, no fork. A stumble is not a corruption.
    expect(verdict.missing, isEmpty);
    expect(verdict.duplicated, isEmpty);
    expect(verdict.mergeCommits, isEmpty);
  });

  test('a join lands while the room is storming, at the bound the product '
      'actually ships', () async {
    // The two barriers collapse into one, so every writer joins while the
    // others are already speaking — a being arriving into a busy room, which
    // is the ordinary case and not an edge. The bound is the product's own.
    //
    // **Was a declared red — intermittent and load-dependent; cured
    // 12/08/2026.** A writer exhausted all eight attempts, stayed outside, and
    // was then refused for every line it said: nothing corrupted, the outcome
    // an honest stumble, and the arriving being silently mute. It was the
    // sharper half of the same defect the gate above carried, because a join
    // that loses costs six lines rather than one.
    //
    // Cured by the same two pieces — full jitter in `LocalChannel._act` and a
    // `defaultAttempts` read off the measured demand. This is the gate that
    // spends the headroom: a join into a live storm was measured needing 12
    // attempts on a loaded machine, which the old bound could not have
    // survived however honest it was about failing.
    final verdict = await storm(
      channel: 'chegada',
      writers: 4,
      lines: 6,
      joinAttempts: defaultAttempts,
      settle: Duration.zero,
    );

    expect(
      verdict.stumbled.where((entry) => entry.startsWith('join/')),
      isEmpty,
      reason: 'a join that stumbles leaves a participant outside the room and '
          'refused for everything it then says — the bound must carry the '
          'ordinary case of four beings arriving together',
    );
    expect(verdict.rosterAbsent, isEmpty);
    expect(verdict.refused, isEmpty);
  });

  test('four writers join a channel that does not exist yet: joining is the '
      'one door in, and four beings walking through it at once is the '
      'ordinary way a new room comes to exist', () async {
    // **Was a declared red, and a deterministic one; cured 12/08/2026.** The
    // storm found it on its first run: three of four writers died inside
    // `Channel.join` with a raw git error — `fatal: a branch named
    // '<channel>' already exists`. `join` births through
    // `ChatActs.ensureBorn`, which read `born` and then created: a plain
    // `git branch`, no compare-and-swap, so every writer through the gap got
    // an exception out of a surface that promises one of four outcomes.
    //
    // The cure is the guarded birth, and it landed **at the primitive**, where
    // the fact lives: `Instance.ensureBorn` swaps the ref from nothing through
    // `Git.updateRef(expected: null)` — the substrate's own *this must not
    // exist* — so the losers of that swap find the instance born rather than
    // broken. A birth race belongs to every entity an external will enters
    // through, and never to chat.
    //
    // The falsifier, run once: put `git branch` back and this gate returns
    // `threw: join/w2, join/w3 … already exists` with both absent from the
    // roster.
    final verdict = await storm(
      channel: 'nascente',
      writers: 4,
      lines: 2,
      birthFirst: false,
    );

    expect(
      verdict.threw,
      isEmpty,
      reason: 'an act reports one of four outcomes and never throws the '
          "substrate's own words at its caller — R1.14",
    );
    expect(
      verdict.rosterAbsent,
      isEmpty,
      reason: 'every writer that joined is in the roster — R1.1, and R1.5 '
          'names two joining at once beside two speaking at once',
    );
    expect(verdict.refused, isEmpty);
    expect(verdict.missing, isEmpty);
    expect(verdict.mergeCommits, isEmpty);
  });
}

/// A reader of the channel, built as any caller builds one. It speaks under a
/// voice of its own that never joins: reading is not membership.
Channel _read(
  String name, {
  required String at,
  String as = 'Judge <judge@storm.test>',
}) {
  final entity = Entity('bentos.chat', from: at);
  final identity = parseStatedIdentity(as);
  return channelConstruction(
    name: name,
    acts: EntityActs(entity.instance(name), identity: identity),
    tree: EntityTree(entity.instance(name)),
    identity: identity,
    ticker: () => DispatchTicker(entity),
  );
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
