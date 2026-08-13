/// The storm: N real writers, one channel, one instant.
///
/// **Why processes.** The laws under judgement here — R1.5 (simultaneous speech
/// never reaches a human as a conflict), R1.14/R1.15 (an act says which of four
/// things happened, and names what it landed as) and the channel's own *every
/// act retries its own swap, bounded by attempts* — quantify over an isolation
/// boundary. What contends is one Git reference, and every act is a
/// read-modify-write of it: read the tip, build on it, swap. Two writers that
/// read one tip and both swap it is where a message is dropped in silence.
/// A witness inside one process cannot vary that, because the awaits serialize
/// the very thing under test — and the green it produces reads exactly like the
/// strong kind. So the writer is a program, launched as an operating-system
/// process, and it is a separate program precisely so the same plan can be
/// launched somewhere else.
///
/// **Three parts, and they do not touch.** [WriterPlan] is the currency — one
/// writer, stated in argv. [StormLaunch] is how a plan becomes a running
/// process: [LocalStormLaunch] today, an `ssh` launch when the two-machine
/// proof is taken. [judge] is pure over what came back plus one real read of
/// the channel, so the verdict is the same verdict whoever launched.
///
/// **What this apparatus does not witness, and does not pretend to.** Every
/// local writer contends over *one clone*. The cross-clone axis — two
/// repositories, a remote between them, a push race — is a second population
/// this gate never varies, and it is reported owed rather than argued from
/// here.
library;

import 'dart:convert';
import 'dart:io';

import 'package:bentos_userland/bentos_chat.dart';

/// What one writer was told to do — argv, as a value, so that launching it
/// locally and launching it over a network differ in the transport alone.
final class WriterPlan {
  const WriterPlan({
    required this.writer,
    required this.place,
    required this.channel,
    required this.identity,
    required this.lines,
    required this.startAt,
    this.speakAt,
    this.attempts = defaultAttempts,
    this.joinAttempts = defaultAttempts,
    this.cadence = Duration.zero,
    this.payloadBytes = 4096,
  });

  /// This writer's name, carried in every line it says: the key the judge
  /// matches the transcript on.
  final String writer;

  /// The place the coordinate resolves from — a directory on the machine the
  /// writer runs on, which is why it travels in the plan and is not inferred.
  final String place;

  final String channel;

  /// `Name <email>`, as `--identity` spells it.
  final String identity;

  final int lines;

  /// The barrier: a wall-clock instant, not a rendezvous on a shared disk.
  /// A file barrier works between processes on one machine and fails the
  /// moment the writers are on two, so the mechanism that survives the move is
  /// the one used from the start. It costs a clock assumption instead: two
  /// machines whose clocks disagree by more than the burst simply do not
  /// overlap, which [StormVerdict.overlapObserved] then reports rather than
  /// passes over.
  final DateTime startAt;

  /// The second barrier: when speech begins. Absent, it is [startAt] and the
  /// two phases are one storm. Given, the writers join at the first instant
  /// and speak at the second — which is how the speech claims are judged
  /// against a settled roster instead of against whatever the join phase left
  /// behind. **One gate, one claim**: a writer that never got in says nothing
  /// about simultaneous speech.
  final DateTime? speakAt;

  /// The bound on the acts under judgement — the speech.
  final int attempts;

  /// The bound on the join, held apart on purpose: the falsifier removes the
  /// retry from what it is judging, and a writer whose *join* stumbled is
  /// refused for every line afterwards — a red made of the setup collapsing
  /// rather than of the claim failing.
  final int joinAttempts;

  /// Between one line and the next. Zero is the sharpest storm.
  final Duration cadence;

  /// Padding on each line. The size axis is not load-bearing here — each act
  /// writes its own file and the contended object is the reference, not one
  /// appended file — so this exists to keep the tree honest-sized rather than
  /// to make a lost update observable.
  final int payloadBytes;

  List<String> get arguments => [
        '--writer', writer,
        '--place', place,
        '--channel', channel,
        '--identity', identity,
        '--lines', '$lines',
        '--start-at', startAt.toUtc().toIso8601String(),
        '--speak-at', (speakAt ?? startAt).toUtc().toIso8601String(),
        '--attempts', '$attempts',
        '--join-attempts', '$joinAttempts',
        '--cadence-ms', '${cadence.inMilliseconds}',
        '--payload-bytes', '$payloadBytes',
      ];
}

/// Which of the four things an act reported. The four never flatten: a stumble
/// is not a refusal, and a throw is neither.
enum ActOutcome { acted, refused, stumbled, threw }

/// One act, as the writer that performed it saw it.
final class ActRecord {
  const ActRecord({
    required this.key,
    required this.outcome,
    required this.startedAt,
    required this.endedAt,
    required this.attempts,
    required this.contested,
    this.commit,
    this.detail,
  });

  factory ActRecord.fromJson(Map<String, Object?> json) => ActRecord(
        key: json['key'] as String,
        outcome: ActOutcome.values.byName(json['outcome'] as String),
        startedAt: DateTime.parse(json['startedAt'] as String),
        endedAt: DateTime.parse(json['endedAt'] as String),
        attempts: json['attempts'] as int,
        contested: json['contested'] as int,
        commit: json['commit'] as String?,
        detail: json['detail'] as String?,
      );

  /// The first line of what was said — `storm/<writer>/<seq>`, unique, and
  /// matched whole rather than by containment.
  final String key;

  final ActOutcome outcome;
  final DateTime startedAt;
  final DateTime endedAt;

  /// How many times the act bracket was opened for this one act, counted at
  /// the seam by the writer itself. `Acted` carries no attempt count of its
  /// own, so this is the only place contention is visible when the act
  /// eventually lands.
  final int attempts;

  /// How many of those attempts came back contested — the ref having moved
  /// under them. **This is the measure that says the storm was a storm.**
  final int contested;

  final String? commit;
  final String? detail;

  Map<String, Object?> toJson() => {
        'key': key,
        'outcome': outcome.name,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'endedAt': endedAt.toUtc().toIso8601String(),
        'attempts': attempts,
        'contested': contested,
        'commit': commit,
        'detail': detail,
      };
}

/// What one writer reported when its process ended.
final class WriterReport {
  const WriterReport({
    required this.writer,
    required this.email,
    required this.pid,
    required this.join,
    required this.lines,
    this.fault,
  });

  factory WriterReport.fromJson(Map<String, Object?> json) => WriterReport(
        writer: json['writer'] as String,
        email: json['email'] as String,
        pid: json['pid'] as int,
        join: ActRecord.fromJson(json['join'] as Map<String, Object?>),
        lines: [
          for (final line in json['lines'] as List<Object?>)
            ActRecord.fromJson(line as Map<String, Object?>),
        ],
        fault: json['fault'] as String?,
      );

  final String writer;
  final String email;
  final int pid;
  final ActRecord join;
  final List<ActRecord> lines;

  /// What killed the writer before it finished, if anything. A writer that
  /// died is a finding, never a gap to be filled in by the judge.
  final String? fault;

  /// The interval this writer was actually speaking in — the only honest input
  /// to *did these two ever overlap*.
  DateTime? get spokeFrom => lines.isEmpty ? null : lines.first.startedAt;
  DateTime? get spokeUntil => lines.isEmpty ? null : lines.last.endedAt;

  Map<String, Object?> toJson() => {
        'writer': writer,
        'email': email,
        'pid': pid,
        'join': join.toJson(),
        'lines': [for (final line in lines) line.toJson()],
        'fault': fault,
      };
}

/// How a plan becomes a running writer. One implementation today; the
/// two-machine proof is a second one, and nothing above this line changes when
/// it arrives.
abstract interface class StormLaunch {
  /// Runs one writer to completion and returns what it reported.
  Future<WriterReport> run(WriterPlan plan);
}

/// Writers as local operating-system processes.
final class LocalStormLaunch implements StormLaunch {
  const LocalStormLaunch({this.packageRoot = '.', this.executable = 'dart'});

  /// Where `test/chat/material/storm_writer.dart` is found from.
  final String packageRoot;

  final String executable;

  static const String script = 'test/chat/material/storm_writer.dart';

  @override
  Future<WriterReport> run(WriterPlan plan) async {
    final result = await Process.run(
      executable,
      ['run', script, ...plan.arguments],
      workingDirectory: packageRoot,
    );
    final out = '${result.stdout}'.trim();
    if (out.isEmpty) {
      throw StateError(
        'writer ${plan.writer} printed no report (exit ${result.exitCode})\n'
        '${result.stderr}',
      );
    }
    return WriterReport.fromJson(
      jsonDecode(out.split('\n').last) as Map<String, Object?>,
    );
  }
}

/// Launches every plan **at once** and collects what each reported. Nothing is
/// staggered here: the barrier is the writers' own, and starting them
/// sequentially is how a storm quietly becomes a queue.
Future<List<WriterReport>> stormOf(
  Iterable<WriterPlan> plans, {
  StormLaunch launch = const LocalStormLaunch(),
}) =>
    Future.wait([for (final plan in plans) launch.run(plan)]);

/// The verdict: every question the storm was raised to answer, each answered
/// separately, so a gate asserts claims rather than a colour.
final class StormVerdict {
  const StormVerdict({
    required this.reports,
    required this.landed,
    required this.transcriptKeys,
    required this.missing,
    required this.duplicated,
    required this.misattributed,
    required this.stumbled,
    required this.refused,
    required this.threw,
    required this.faults,
    required this.mergeCommits,
    required this.residue,
    required this.rosterAbsent,
    required this.contendedActs,
    required this.attemptsNeeded,
    required this.overlaps,
    required this.writers,
  });

  final List<WriterReport> reports;

  /// Keys the writers reported as landed — what they claim they wrote.
  final List<String> landed;

  /// Keys actually in the transcript, in arrival order.
  final List<String> transcriptKeys;

  /// Claimed landed and not in the transcript: **the lost update.**
  final List<String> missing;

  /// In the transcript more than once.
  final List<String> duplicated;

  /// In the transcript under another writer's handle.
  final List<String> misattributed;

  final List<String> stumbled;
  final List<String> refused;
  final List<String> threw;

  /// Writers that died.
  final List<String> faults;

  /// A merge commit on the channel's line — R1.5's failure, made of git.
  final List<String> mergeCommits;

  /// Anything the storm left in the medium's repository: a dirty worktree, a
  /// merge in progress, an area not released.
  final List<String> residue;

  final List<String> rosterAbsent;

  /// Acts that saw the reference move under them at least once.
  final int contendedActs;

  /// **How many attempts each act actually needed** — every act of every
  /// writer, in no order, one entry each. The colour says whether the shipped
  /// bound held; this says by how much, and it is the only reading a bound can
  /// honestly be chosen from. An act that stumbled contributes the bound it
  /// reached, which is a floor on its demand and not its demand.
  final List<int> attemptsNeeded;

  /// [attemptsNeeded] as a histogram, attempts → acts.
  Map<int, int> get attemptHistogram {
    final counts = <int, int>{};
    for (final n in attemptsNeeded) {
      counts[n] = (counts[n] ?? 0) + 1;
    }
    return Map.fromEntries(
      counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  /// The worst demand observed. Zero when nothing acted.
  int get worstAttempts =>
      attemptsNeeded.isEmpty ? 0 : attemptsNeeded.reduce((a, b) => a > b ? a : b);

  /// **What an act cost in wall clock**, worst first. The attempt count says
  /// whether the bound holds; this says what holding it feels like to whoever
  /// is waiting — a retry that waits is latency, and a bound chosen without
  /// reading it buys reliability with a delay nobody measured.
  List<Duration> get actDurations => [
        for (final report in reports)
          for (final act in [report.join, ...report.lines])
            act.endedAt.difference(act.startedAt),
      ]..sort((a, b) => b.compareTo(a));

  /// Pairs of writers whose speaking intervals intersect.
  final List<String> overlaps;

  final List<String> writers;

  /// Did the writers actually speak at the same time? A storm that did not
  /// overlap proves nothing about simultaneity, whatever colour it returns.
  bool get overlapObserved => overlaps.isNotEmpty;

  /// Did anything actually contend? Overlap in time with no contention at the
  /// reference means the acts still never met, and the run must say so instead
  /// of passing.
  bool get contentionObserved => contendedActs > 0;

  /// Every claim the storm makes when it is clean.
  bool get clean =>
      missing.isEmpty &&
      duplicated.isEmpty &&
      misattributed.isEmpty &&
      stumbled.isEmpty &&
      refused.isEmpty &&
      threw.isEmpty &&
      faults.isEmpty &&
      mergeCommits.isEmpty &&
      residue.isEmpty &&
      rosterAbsent.isEmpty;

  /// Printed by every run, green or red. A run that did not race says so here
  /// in the same breath as its results, because the two together are the whole
  /// of what happened.
  ///
  /// **The distribution comes first, before any count of what went wrong.** A
  /// bound is a claim about a distribution, so a gate that reports only the
  /// colour hides the measure that makes the colour worth anything — and the
  /// number a future reader must set the bound from is exactly this line.
  String describe() {
    final b = StringBuffer()
      ..writeln('  attempts needed: '
          '${attemptHistogram.entries.map((e) => '${e.key}×${e.value}').join('  ')}'
          '   worst=$worstAttempts of ${attemptsNeeded.length} act(s)')
      ..writeln('  slowest acts (ms): '
          '${actDurations.take(5).map((d) => d.inMilliseconds).join(', ')}')
      ..writeln('storm: ${writers.length} writers, '
          '${landed.length} lines claimed landed, '
          '${transcriptKeys.length} in the transcript')
      ..writeln('  raced: overlap=${overlaps.length} pair(s), '
          'contended acts=$contendedActs');
    void note(String label, List<String> what) {
      if (what.isNotEmpty) b.writeln('  $label: ${what.join(', ')}');
    }
    note('MISSING (lost update)', missing);
    note('DUPLICATED', duplicated);
    note('MISATTRIBUTED', misattributed);
    note('stumbled', stumbled);
    note('refused', refused);
    note('threw', threw);
    note('writer faults', faults);
    note('MERGE COMMITS', mergeCommits);
    note('residue', residue);
    note('absent from roster', rosterAbsent);
    return b.toString();
  }
}

/// Reads the world the storm ran over and says what happened.
///
/// The transcript is read through the library, the reference through git —
/// two mechanisms, because *no conflict reached a human* is a claim about the
/// shape of the line and the library has no vocabulary for a merge commit.
Future<StormVerdict> judge({
  required List<WriterReport> reports,
  required Channel channel,
  required String repository,
  required String ref,
}) async {
  final landed = <String>[];
  final stumbled = <String>[];
  final refused = <String>[];
  final threw = <String>[];
  final faults = <String>[];
  final attemptsNeeded = <int>[];
  var contendedActs = 0;

  for (final report in reports) {
    if (report.fault != null) faults.add('${report.writer}: ${report.fault}');
    for (final act in [report.join, ...report.lines]) {
      if (act.contested > 0) contendedActs++;
      attemptsNeeded.add(act.attempts);
      // The join is an act like any other and contends like any other, but it
      // deposits no line: only speech is looked for in the transcript.
      final speech = act != report.join;
      switch (act.outcome) {
        case ActOutcome.acted:
          if (speech) landed.add(act.key);
        case ActOutcome.stumbled:
          stumbled.add('${act.key} (${act.attempts} attempts)');
        case ActOutcome.refused:
          refused.add('${act.key}: ${act.detail}');
        case ActOutcome.threw:
          threw.add('${act.key}: ${act.detail}');
      }
    }
  }

  final transcript = await channel.history();
  final keys = [for (final m in transcript) m.body.split('\n').first];
  final author = <String, String>{
    for (final m in transcript) m.body.split('\n').first: m.author.local,
  };

  final counts = <String, int>{};
  for (final key in keys) {
    counts[key] = (counts[key] ?? 0) + 1;
  }

  final missing = [for (final key in landed) if (!counts.containsKey(key)) key];
  final duplicated = [
    for (final entry in counts.entries) if (entry.value > 1) entry.key,
  ];

  final ownerOf = <String, String>{
    for (final report in reports)
      for (final act in report.lines)
        act.key: Handle.ofEmail(report.email).local,
  };
  final misattributed = [
    for (final key in keys)
      if (ownerOf.containsKey(key) && author[key] != ownerOf[key])
        '$key: said by ${ownerOf[key]}, attributed to ${author[key]}',
  ];

  final roster = await channel.roster();
  final rosterAbsent = [
    for (final report in reports)
      if (!roster.contains(Handle.ofEmail(report.email))) report.writer,
  ];

  final merges = _git(repository, ['rev-list', '--min-parents=2', ref])
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .toList();

  final residue = _residue(repository);

  final overlaps = <String>[];
  for (var i = 0; i < reports.length; i++) {
    for (var j = i + 1; j < reports.length; j++) {
      final a = reports[i];
      final b = reports[j];
      final from = a.spokeFrom, until = a.spokeUntil;
      final otherFrom = b.spokeFrom, otherUntil = b.spokeUntil;
      if (from == null || until == null || otherFrom == null || otherUntil == null) {
        continue;
      }
      if (from.isBefore(otherUntil) && otherFrom.isBefore(until)) {
        overlaps.add('${a.writer}×${b.writer}');
      }
    }
  }

  return StormVerdict(
    reports: reports,
    landed: landed,
    transcriptKeys: keys,
    missing: missing,
    duplicated: duplicated,
    misattributed: misattributed,
    stumbled: stumbled,
    refused: refused,
    threw: threw,
    faults: faults,
    mergeCommits: merges,
    residue: residue,
    rosterAbsent: rosterAbsent,
    contendedActs: contendedActs,
    attemptsNeeded: attemptsNeeded,
    overlaps: overlaps,
    writers: [for (final report in reports) report.writer],
  );
}

/// What the storm left behind in the medium's own repository.
///
/// The repository is **bare** — the entity keeps its state as refs and opens a
/// private worktree per act, under `<git-dir>/acts`, released in a `finally`.
/// So the residue question is not *is the worktree dirty* (there is none to be
/// dirty) but *did any act keep its area*, plus the ordinary marks of a merge
/// nobody finished. Asking a bare repository for `status` is how this check
/// first got a fatal error instead of an answer.
List<String> _residue(String repository) {
  final gitDir = _git(repository, ['rev-parse', '--absolute-git-dir']).trim();
  final residue = <String>[
    if (File('$gitDir/MERGE_HEAD').existsSync()) 'a merge is in progress',
  ];

  final areas = Directory('$gitDir/acts');
  if (areas.existsSync()) {
    for (final left in areas.listSync()) {
      residue.add('an act kept its private area: ${left.path}');
    }
  }

  // A released area also unregisters; one still registered is the other half
  // of the same leak, and it survives the directory being gone.
  for (final line in _git(repository, ['worktree', 'list', '--porcelain']).split('\n')) {
    if (line.startsWith('worktree ') && line.contains('/acts/')) {
      residue.add('a worktree is still registered: ${line.substring(9)}');
    }
  }

  if (_git(repository, ['rev-parse', '--is-bare-repository']).trim() != 'true') {
    for (final line in _git(repository, ['status', '--porcelain']).split('\n')) {
      if (line.trim().isNotEmpty) residue.add('dirty: ${line.trim()}');
    }
  }
  return residue;
}

String _git(String repository, List<String> arguments) {
  final result = Process.runSync('git', ['-C', repository, ...arguments]);
  if (result.exitCode != 0) {
    throw StateError(
      'git ${arguments.join(' ')} in $repository → ${result.exitCode}\n'
      '${result.stderr}',
    );
  }
  return '${result.stdout}';
}
