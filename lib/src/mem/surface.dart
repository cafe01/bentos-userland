import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../cli/positional_grammar.dart';
import '../git/model/actor.dart';
import 'account.dart';
import 'attention.dart';
import 'bank.dart';
import 'index.dart';
import 'nearest.dart';
import 'page.dart';
import 'walk.dart';
import 'writer.dart';

/// The whole tool, as one call. `bin/mem.dart` reads the working directory
/// and the arguments and does nothing else — it is the one file the import
/// law does not bind, and the only place a vantage, the environment or stdin
/// is observed. Everything this class needs from that boundary arrives
/// through its constructor instead of being read here.
final class Mem {
  Mem({
    required this.vantage,
    required this.out,
    required this.diagnostics,
    required this.environment,
    this.stdinReader,
    this.fileReader,
    this.gistSource,
  }) {
    _runner = CommandRunner<void>(
      'mem',
      'The organ of the brain — the pen that writes it and the recall that '
          'reads it.',
    )
      ..argParser.addOption(
        'bank',
        abbr: 'b',
        help: 'The bank this command addresses. Falls back to \$BENTOS_AGENT.',
        valueHelp: 'bank',
      )
      ..argParser.addOption(
        'place',
        abbr: 'p',
        help: 'The vantage name resolution walks up from.',
        valueHelp: 'place',
      )
      ..argParser.addOption(
        'age',
        help: 'How a page states its age: stamp (a date, the default and the '
            'only stable one), relative (against the clock now), none.',
        valueHelp: 'mode',
        allowed: ['stamp', 'relative', 'none'],
        defaultsTo: 'stamp',
      )
      ..argParser.addOption(
        'actor',
        help: 'Who is writing: "Name <addr>". Required by every verb that '
            'writes — a page landed under whoever owns this machine is a '
            'signed lie, and nothing here derives an identity.',
        valueHelp: 'who',
      )
      ..addCommand(SurveyCommand(this))
      ..addCommand(RecallCommand(this))
      ..addCommand(WalkCommand(this))
      ..addCommand(HealthCommand(this))
      ..addCommand(RememberCommand(this))
      ..addCommand(RefocusCommand(this))
      ..addCommand(GistCommand(this))
      ..addCommand(TagCommand(this))
      ..addCommand(ForgetCommand(this));
  }

  /// The vantage `bin/mem.dart` observed — the working directory, or a path
  /// given explicitly. `-p` composes against this one; nothing else reads it.
  final String vantage;

  final Sink<String> out;
  final Sink<String> diagnostics;

  /// The process environment, for `$BENTOS_AGENT` — read once by the caller
  /// and handed in, since `dart:io` is out of reach under `mem/`.
  final Map<String, String> environment;

  /// Reads the body from stdin for a write with no `-f`. Null when the host
  /// cannot offer one (an inherited terminal) — a write that needs it then
  /// refuses with a usage error rather than blocking on an EOF that won't
  /// come.
  final Future<String> Function()? stdinReader;

  /// Reads `-f <path>`'s file, given the path exactly as typed. Null on a
  /// host offering no file access — `-f` then reports the same usage fault
  /// a nonexistent path would.
  final Future<String> Function(String path)? fileReader;

  /// The model seam. Null means no model is reachable, which every verb that
  /// needs a derived gist must treat as an ordinary refusal (R8) — never a
  /// crash, and never a default this component invents.
  final GistSource? gistSource;

  late final CommandRunner<void> _runner;

  /// **0** — did what was asked, including an empty reach on a browsing
  /// verb (`survey`, `walk`) and a degraded read. **1** — a decided refusal,
  /// a bank not found from the vantage, or a verb aimed at a named target
  /// (`recall`, `refocus`, `tag`, `gist`) that found none of it: a total
  /// miss on a directed lookup is a failure the caller must be able to
  /// branch on, distinct from an empty reach while browsing. A *partial*
  /// miss — some named targets found, some not — stays **0**, with the
  /// misses named in the frame. **2** — the call itself was invalid. **3**
  /// — the act landed and the line carries it, but the local working tree
  /// did not follow (TREE STALE, NO TREE): distinct from **1** on purpose,
  /// because a caller that greps for one exit code to mean *nothing
  /// happened* must not be lied to twice — first by a clean-looking
  /// `written` line, then by a refusal code on a write that in fact landed.
  /// **64** — nobody said who is writing.
  int exitCode = 0;

  /// The act landed; only the local tree's own materialization lagged. See
  /// [exitCode]'s **3**.
  static const int materializationLagCode = 3;

  Future<int> call(List<String> arguments) async {
    exitCode = 0;
    try {
      await _runner.run(arguments);
    } on NoActor catch (e) {
      // **64 and not 2**, though both mean the call was not sayable. A caller
      // scripting across `entity`, `chat` and `mem` must read one number for
      // *you did not say who you are*: the refusal is the platform's, not this
      // utility's, and a shared law that answers with three different codes is
      // three laws.
      diagnostics.add('$e\n');
      exitCode = 64;
    } on UsageException catch (e) {
      diagnostics.add('${_annotateUsage(e.message)}\n');
      exitCode = 2;
    }
    return exitCode;
  }

  /// `unknown-option` (§6): fires in the argument-parsing failure path, not
  /// over a computed [Account] — no verb has run yet when the parser itself
  /// rejects a flag it does not know. A retired name answers exactly, from
  /// the one place a dead flag name is allowed to survive; anything else is
  /// answered by the same nearest-name search a mistyped topic gets.
  /// Every other [UsageException] — arity, wrong-bank citations, and the
  /// rest a verb throws itself via `usageException` — passes through
  /// unchanged; only the args package's own "no such option" wears this
  /// voice.
  static final _unknownLongOption =
      RegExp(r'^Could not find an option named "--([^"]+)"\.$');

  /// `--dry-run` → `--shape` (§7), and the only place a retired name lives:
  /// no alias, no hidden flag — the caller who types it is told the live one.
  static const _retiredOptions = {'dry-run': 'shape'};

  String _annotateUsage(String message) {
    final match = _unknownLongOption.firstMatch(message);
    if (match == null) return message;
    final typed = match.group(1)!;
    final retired = _retiredOptions[typed];
    if (retired != null) return 'mem: no option --$typed. Did you mean --$retired?';
    final nearest = nearestNames(typed, _allOptionNames, cap: 1);
    if (nearest.isEmpty) return 'mem: no option --$typed.';
    return 'mem: no option --$typed. Did you mean --${nearest.first}?';
  }

  /// Every long option this tool declares, global and per-verb — the
  /// candidate pool `unknown-option`'s nearest-name search ranks against.
  /// Coarser than "the options the failing verb declares": the parser's own
  /// error does not say which command it was resolving against once it has
  /// walked up to the parent, and a slightly wider pool costs nothing a
  /// caller would notice.
  late final Set<String> _allOptionNames = {
    ..._runner.argParser.options.keys,
    for (final command in _runner.commands.values) ...command.argParser.options.keys,
  };
}

/// How a page states its age — **a rendering register of the whole tool, not
/// an argument of one verb**, so `survey`, `recall` and `walk` all obey one
/// switch.
///
/// [stamp] is the default because this tool's largest reader is a mind being
/// staged: a walk's output is a prompt prefix, billed on every turn of the
/// life it opens, and a clock-derived byte anywhere in it invalidates the
/// cache of everything after it for no change in the bank. A date changes
/// only when the page does. [relative] is the reader's mode at a terminal,
/// and it is the only one that consults the clock at all.
enum AgeRender { stamp, relative, none }

/// Nobody stated who is writing, or what they stated is not `Name <addr>`.
///
/// **A refusal with a name, never a fallback**: a fallback here produces a
/// signed lie rather than a failure, and the page would carry it forever.
final class NoActor implements Exception {
  const NoActor();

  @override
  String toString() => 'mem: say who is writing — pass --actor "Name <addr>". '
      'Both halves are required, and nothing else may answer: the git identity '
      'cascade describes whoever owns a checkout on this machine, not whoever '
      'is remembering.';
}

/// The base every verb stands on: the two globals, bank resolution, and the
/// selector grammar shared by every verb that reaches more than one topic.
/// The positional grammar itself — labels, arity, the optional floor and the
/// repeating tail — is [PositionalGrammar], the contract shared with
/// `entity`: mem's own middle tier (`health`, `refocus`, `tag`, `gist`)
/// states [PositionalGrammar.minPositionals] as `0`, and `recall`/`walk`
/// state [PositionalGrammar.repeating] as `true` — the two facts `entity`
/// never needed to state because every one of its verbs is fixed-arity, the
/// contract's default.
abstract base class MemCommand extends Command<void> with PositionalGrammar {
  MemCommand(this.cli);

  final Mem cli;

  /// `-p`, composed against [Mem.vantage] the way `entity`'s `-C` composes
  /// against its own working directory.
  String get effectiveVantage {
    final place = globalResults?['place'] as String?;
    if (place == null) return cli.vantage;
    final abs = p.isAbsolute(place) ? place : p.join(cli.vantage, place);
    return p.normalize(abs);
  }

  /// `-b`, falling back to `$BENTOS_AGENT` — the kind's own convention, so
  /// every living waking that never names a bank still reaches its own.
  /// Neither present is a usage fault naming both cures.
  String bankName() {
    final named = globalResults?['bank'] as String?;
    final ambient = cli.environment['BENTOS_AGENT'];
    final resolved = named ?? ambient;
    if (resolved == null) {
      usageException(
        '$name: no bank named — pass -b <bank> or set \$BENTOS_AGENT',
      );
    }
    return resolved;
  }

  /// `--actor "Name <addr>"`, or a refusal — **the same law the entity floor
  /// states, reaching the caller nobody enumerated.** A page is landed by an
  /// act and an act carries an author; absent a stated one the machine's git
  /// cascade answered, and a bank written under whoever owns this workstation
  /// attributes one being's memory to another.
  ///
  /// No environment variable softens it. One was considered and refused: a
  /// variable that names a being is not an address, and a file that answers
  /// for a caller who said nothing is the cascade again with better manners.
  Actor statedActor() {
    final stated = (globalResults?['actor'] as String?)?.trim();
    if (stated == null || stated.isEmpty) throw const NoActor();
    final match = RegExp(r'^(.*)<([^<>]+)>$').firstMatch(stated);
    if (match == null) throw const NoActor();
    final who = match.group(1)!.trim();
    final address = match.group(2)!.trim();
    if (who.isEmpty || address.isEmpty || !address.contains('@')) {
      throw const NoActor();
    }
    return Actor(who, email: address);
  }

  /// `--age`, the tool's rendering register for [Page.modified].
  AgeRender ageRender() => switch (globalResults?['age'] as String?) {
        'relative' => AgeRender.relative,
        'none' => AgeRender.none,
        _ => AgeRender.stamp,
      };

  /// Resolves the named bank from [effectiveVantage]. A miss prints the
  /// refusal on the diagnostic channel (R2.1.1), marks the run refused, and
  /// returns null — the caller's cue to stop.
  Bank? resolveBank() {
    final vantage = effectiveVantage;
    final resolution = Bank.resolve(bankName(), vantage: vantage);
    switch (resolution) {
      case Found(:final bank):
        return bank;
      case NotFound(:final tried, :final vantage):
        cli.diagnostics.add(
          'mem: ${tried.join(' nor ')} not found, searched up from $vantage\n',
        );
        cli.exitCode = 1;
        return null;
    }
  }
}

/// The §5 selector grammar — attention band, explicit range, type, tag —
/// shared by every verb that can reach more than one page, and the
/// `<topic> | <selectors>` reading every non-`survey` one of them offers.
base mixin SelectorArgs on MemCommand {
  void declareSelectorFlags() {
    argParser
      ..addFlag('hot', negatable: false, help: 'attention 1.0')
      ..addFlag('warm', negatable: false, help: 'attention 0.7–0.9')
      ..addFlag('cool', negatable: false, help: 'attention 0.4–0.6')
      ..addFlag('cold', negatable: false, help: 'attention 0.1–0.3')
      ..addOption('min-attention', valueHelp: 'A')
      ..addOption('max-attention', valueHelp: 'A')
      ..addOption('type', valueHelp: 'mode')
      ..addOption('tag', valueHelp: 'tag');
  }

  static const _bands = {
    'hot': (1.0, 1.0),
    'warm': (0.7, 0.9),
    'cool': (0.4, 0.6),
    'cold': (0.1, 0.3),
  };

  Selector buildSelector({String? topic, Set<String>? topics}) {
    final chosen = [
      for (final band in _bands.keys)
        if (argResults!.wasParsed(band) && argResults![band] as bool) band,
    ];
    if (chosen.length > 1) {
      usageException('$name: at most one of --hot/--warm/--cool/--cold');
    }

    Attention? min;
    Attention? max;
    if (chosen.isNotEmpty) {
      final (lo, hi) = _bands[chosen.first]!;
      min = Attention(lo);
      max = Attention(hi);
    }

    final minOpt = argResults!['min-attention'] as String?;
    if (minOpt != null) {
      final parsed = _parseAttention(minOpt);
      min = min == null || parsed.tenths > min.tenths ? parsed : min;
    }
    final maxOpt = argResults!['max-attention'] as String?;
    if (maxOpt != null) {
      final parsed = _parseAttention(maxOpt);
      max = max == null || parsed.tenths < max.tenths ? parsed : max;
    }

    final typeOpt = argResults!['type'] as String?;
    MemType? type;
    if (typeOpt != null) {
      try {
        type = MemType.parse(typeOpt);
      } on FormatException catch (e) {
        usageException('$name: ${e.message}');
      }
    }

    return Selector(
      minAttention: min,
      maxAttention: max,
      type: type,
      tag: argResults!['tag'] as String?,
      topic: topic,
      topics: topics,
    );
  }

  Attention _parseAttention(String source) {
    try {
      return Attention.parse(source);
    } on FormatException catch (e) {
      usageException('$name: ${e.message}');
    }
  }

  /// What was asked, in the caller's own words — echoed back on an empty
  /// reach (R5.3) so the caller can see what it actually asked for.
  String reachDescription({String? topic, Set<String>? topics}) {
    if (topic != null) return topic;
    if (topics != null && topics.isNotEmpty) return topics.join(', ');
    final parts = <String>[
      for (final band in _bands.keys)
        if (argResults!.wasParsed(band) && argResults![band] as bool) '--$band',
    ];
    void add(String flag) {
      final v = argResults![flag] as String?;
      if (v != null) parts.add('--$flag $v');
    }

    add('min-attention');
    add('max-attention');
    add('type');
    add('tag');
    return parts.isEmpty ? '(everything)' : parts.join(' ');
  }
}

/// `mem survey [<selectors>] [--limit <n>] [--offset <n>] [--size-threshold <n>]`
final class SurveyCommand extends MemCommand with SelectorArgs {
  SurveyCommand(super.cli) {
    declareSelectorFlags();
    argParser
      ..addOption('limit', valueHelp: 'n')
      ..addOption('offset', valueHelp: 'n', defaultsTo: '0')
      ..addOption('size-threshold', valueHelp: 'n', defaultsTo: '120');
  }

  @override
  String get name => 'survey';

  @override
  String get description => 'The index — one cue line per page, hottest first.';

  @override
  Future<void> run() async {
    final bank = resolveBank();
    if (bank == null) return;
    cli.out.add(_bankHeader(bank.name));
    if (_reportIfNoTree(cli, bank)) return;

    final selector = buildSelector();
    final index = Index.of(bank);
    final matched = index.select(selector);
    final desc = reachDescription();
    final filterDescription = desc == '(everything)' ? '' : desc;

    if (matched.isEmpty) {
      cli.diagnostics.add(renderSurveyFrame(SurveyAccount(
        bank: bank.name,
        shown: 0,
        totalInBank: index.pages.length,
        filterDescription: filterDescription,
        words: 0,
      )));
      return;
    }

    final limitOpt = argResults!['limit'] as String?;
    final limit = limitOpt == null ? null : int.parse(limitOpt);
    final offset = int.parse(argResults!['offset'] as String);
    final threshold = int.parse(argResults!['size-threshold'] as String);

    final total = matched.length;
    final sliced =
        matched.skip(offset).take(limit ?? (total - offset)).toList();

    cli.out.add(_renderSurvey(
      sliced,
      age: ageRender(),
      truncated: offset > 0 || (limit != null && offset + limit < total),
      from: offset + 1,
      to: offset + sliced.length,
      total: total,
      threshold: threshold,
    ));

    final words = sliced.fold(0, (sum, p) => sum + _wordCount(p.body));
    cli.diagnostics.add(renderSurveyFrame(SurveyAccount(
      bank: bank.name,
      shown: sliced.length,
      totalInBank: index.pages.length,
      filterDescription: filterDescription,
      words: words,
    )));
  }
}

/// `mem recall <topic> | <selectors>`
final class RecallCommand extends MemCommand with SelectorArgs {
  RecallCommand(super.cli) {
    declareSelectorFlags();
  }

  @override
  String get name => 'recall';

  @override
  String get description => 'Whole pages, into the frame.';

  @override
  List<String> get positionalLabels => const ['topic'];

  @override
  int get minPositionals => 0;

  @override
  bool get repeating => true;

  @override
  Future<void> run() async {
    final bank = resolveBank();
    if (bank == null) return;
    cli.out.add(_bankHeader(bank.name));
    if (_reportIfNoTree(cli, bank)) return;

    final index = Index.of(bank);
    final seenTopics = <String>{};
    final topics = <String>[];
    for (final raw in requirePositionals()) {
      // `mem://<bank>/<topic>` is accepted alongside a bare topic — the same
      // form `walk` prints back on every skip line and dry-run entry point,
      // so a citation copied out of that output must resolve rather than be
      // read as a literal topic that happens to contain slashes and colons.
      // Naming a foreign bank here is not a miss to report as "no pages": it
      // is the caller asking recall to do what only `walk` does, and it is
      // said plainly rather than folded into the empty-reach path below.
      final address = Address.parse(raw);
      if (address != null && address.bank != bank.name) {
        usageException(
          '$name: $raw names bank ${address.bank}, not the addressed bank '
          '${bank.name} — recall reaches one bank per call, use walk to cross '
          'banks',
        );
      }
      final topic = address?.topic ?? raw;
      if (seenTopics.add(topic)) topics.add(topic);
    }

    final bankTopics = [for (final page in index.pages) page.topic];

    if (topics.isEmpty) {
      final selector = buildSelector();
      final matched = index.select(selector);
      final desc = reachDescription();
      if (matched.isNotEmpty) cli.out.add(_renderRecall(matched, age: ageRender()));
      final words = matched.fold(0, (sum, p) => sum + _wordCount(p.body));
      cli.diagnostics.add(renderRecallFrame(RecallAccount(
        bank: bank.name,
        requestedTopics: const [],
        foundCount: matched.length,
        missingTopics: const [],
        totalInBank: index.pages.length,
        filterDescription: desc == '(everything)' ? '' : desc,
        words: words,
        bankTopics: bankTopics,
      )));
      if (matched.isEmpty) cli.exitCode = 1;
      return;
    }

    // Order is the caller's: each topic is looked up on its own, in the
    // order it was named, and never resorted — recall is a staging verb,
    // and the order named is the order the mind reads.
    final found = <Page>[];
    final missing = <String>[];
    for (final topic in topics) {
      final selector = buildSelector(topic: topic);
      final matched = index.select(selector);
      if (matched.isEmpty) {
        missing.add(topic);
      } else {
        found.addAll(matched);
      }
    }

    if (found.isNotEmpty) cli.out.add(_renderRecall(found, age: ageRender()));
    final words = found.fold(0, (sum, p) => sum + _wordCount(p.body));
    cli.diagnostics.add(renderRecallFrame(RecallAccount(
      bank: bank.name,
      requestedTopics: topics,
      foundCount: found.length,
      missingTopics: missing,
      totalInBank: index.pages.length,
      filterDescription: '',
      words: words,
      bankTopics: bankTopics,
    )));
    // A total miss (every named topic absent) is a failed lookup and must
    // be tellable from a success — exit 1. A partial miss (some found)
    // stays 0: the frame above already names what's missing, and the
    // caller got real pages back.
    if (found.isEmpty) cli.exitCode = 1;
  }
}

/// `mem walk <mem://bank/topic>... [<selectors>] [--depth <n>]`
final class WalkCommand extends MemCommand with SelectorArgs {
  WalkCommand(super.cli) {
    declareSelectorFlags();
    argParser
      ..addOption('depth', valueHelp: 'n')
      ..addFlag(
        'cross-bank',
        negatable: false,
        help: 'Follow a link out of the bank that wrote it. Off by default: '
            'a citation into another bank stands in the prose but is not '
            'traversed, so the author who cites freely never sets the '
            'composer\'s cost.',
      )
      ..addFlag(
        'shape',
        negatable: false,
        help: 'The set, not the composition: which pages enter, at what '
            'ring, and which do not, and why. --dry-run retired to this name.',
      );
  }

  @override
  String get name => 'walk';

  @override
  String get description => 'Traversal from entry points, outward, level by level.';

  @override
  List<String> get positionalLabels => const ['entry'];

  @override
  bool get repeating => true;

  @override
  Future<void> run() async {
    final entries = <Address>[];
    for (final raw in requirePositionals()) {
      final address = Address.parse(raw);
      if (address == null) {
        usageException('$name: not an entry point (mem://<bank>/<topic>): $raw');
      }
      entries.add(address);
    }

    final vantage = effectiveVantage;
    final hasSelector = ['hot', 'warm', 'cool', 'cold', 'min-attention',
            'max-attention', 'type', 'tag']
        .any((f) => argResults!.wasParsed(f));
    final depthOpt = argResults!['depth'] as String?;
    final filter = hasSelector ? buildSelector() : null;

    final walk = Walk(
      vantage: vantage,
      filter: filter,
      depth: depthOpt == null ? null : int.parse(depthOpt),
      crossBank: argResults!['cross-bank'] as bool,
    );
    final walked = await walk.from(entries);

    // The walk's own NO TREE: a bank resolved but never materialized, so
    // reading its pages would have answered `[]` for every entry it holds
    // and each one would have shown up as an ordinary dead link. Same voice
    // and exit code as [_reportIfNoTree], one bank at a time — walk cannot
    // share that helper directly, since it opens banks itself mid-drain
    // rather than through [resolveBank]. Left exactly as it was (§6: the
    // rule that does not change).
    final noTreeBanks = <String>{
      for (final skip in walked.skipped)
        if (skip.reason == SkipReason.noTree) skip.address.bank,
    };
    for (final bankName in noTreeBanks) {
      final resolution = Bank.resolve(bankName, vantage: vantage);
      if (resolution is Found) {
        cli.diagnostics.add(
          'mem: ${resolution.bank.name} — NO TREE: no tree of this bank '
          'stands at ${resolution.bank.materializationAddress.path}, so '
          'nothing is readable here. Materialize it.\n',
        );
      }
      cli.exitCode = Mem.materializationLagCode;
    }

    final shape = argResults!['shape'] as bool;
    final home = entries.first.bank;

    // No branch here prints: an empty reach is not a special case to say
    // early, it is a fact the frame below already carries — the command
    // echo names the entry points, and the weight line reads 0 pages, 0
    // words, 0 links followed. A second sentence here would restate it from
    // a second home (R1.1, R2.4).
    if (shape) {
      cli.out.add(_renderShape(walked, home: home));
    } else {
      cli.out.add(_renderComposition(
        walked.reached,
        home: home,
        age: ageRender(),
      ));
    }

    final account = WalkAccount(
      bank: home,
      commandEcho: _walkCommandEcho(entries, argResults!, shape: shape),
      reached: walked.reached,
      skipped: walked.skipped,
      weight: walked.weight,
      hotUnreachable: _hotUnreachable(vantage, entries, filter, walked),
    );
    cli.diagnostics.add(renderWalkFrame(account));
  }
}

/// `mem health [<topic>] [<selectors>]`
final class HealthCommand extends MemCommand with SelectorArgs {
  HealthCommand(super.cli) {
    declareSelectorFlags();
  }

  @override
  String get name => 'health';

  @override
  String get description =>
      'What links here, what this links to, what is orphaned, what is dead. '
      'Bare, this counts every type together, journals included. Pass '
      '--type to read one type at a time; summed over every type but '
      'autobiographical, that is the real defect count.';

  @override
  List<String> get positionalLabels => const ['topic'];

  @override
  int get minPositionals => 0;

  @override
  Future<void> run() async {
    final bank = resolveBank();
    if (bank == null) return;
    cli.out.add(_bankHeader(bank.name));
    if (_reportIfNoTree(cli, bank)) return;

    final index = Index.of(bank);
    final topic = optionalPositional();

    if (topic != null) {
      // This view lists edges; it never resolves a `bank`-qualified one
      // against anything, sibling installed or not — the caveat that named
      // that limitation belongs here regardless of what the full-health
      // path below can now do.
      cli.diagnostics.add(
        'mem: ${bank.name} — health, this bank alone; external links unjudged.\n',
      );
      final out = index.outbound(topic);
      final inb = index.inbound(topic);
      final buf = StringBuffer()
        ..writeln('outbound of $topic (${out.length}):');
      for (final edge in out) {
        buf.writeln('  ${edge.bank == null ? edge.topic : '${edge.bank}/${edge.topic}'}');
      }
      buf.writeln('inbound to $topic (${inb.length}):');
      for (final edge in inb) {
        buf.writeln('  ${edge.from}');
      }
      cli.out.add(buf.toString());
      return;
    }

    // The banks this bank's own pages actually name, resolved from the same
    // vantage `bank` itself was — not gone looking for, not `materializedAt`
    // reached around, the same `Bank.resolve` / `hasTree` pair [walk] already
    // uses to open a sibling mid-drain. A name that does not resolve, or
    // resolves with no tree standing, is simply absent from the map: that is
    // "not installed here", and it is what keeps a link to a bank nobody has
    // honestly unjudged rather than a false accusation.
    final named = <String>{
      for (final page in index.pages)
        for (final edge in index.outbound(page.topic))
          if (edge.bank != null) edge.bank!,
    };
    final siblingTopics = <String, Set<String>>{
      for (final name in named)
        if (Bank.resolve(name, vantage: bank.vantage) case Found(bank: final sibling)
            when sibling.hasTree)
          name: {for (final p in sibling.pages()) p.topic},
    };

    final hasSelector = ['hot', 'warm', 'cool', 'cold', 'min-attention',
            'max-attention', 'type', 'tag']
        .any((f) => argResults!.wasParsed(f));
    final health = index.health(
      within: hasSelector ? buildSelector() : null,
      siblingTopics: siblingTopics,
    );

    final judged = [
      for (final d in health.dead)
        if (d.kind != DeadKind.bankNotFound) d,
    ];
    final unjudged = [
      for (final d in health.dead)
        if (d.kind == DeadKind.bankNotFound) d,
    ];

    final buf = StringBuffer()
      ..writeln('orphans (${health.orphans.length}):');
    for (final t in health.orphans) {
      buf.writeln('  $t');
    }
    buf.writeln('dead links (${judged.length}):');
    for (final d in judged) {
      final target = d.bank == null ? d.topic : '${d.bank}/${d.topic}';
      final note = d.foundIn == null ? '' : ' (found in ${d.foundIn})';
      buf.writeln('  ${d.from} (${d.fromType.name}) -> $target [${d.kind.name}]$note');
    }
    if (unjudged.isNotEmpty) {
      buf.writeln('external, unjudged (${unjudged.length}):');
      for (final d in unjudged) {
        buf.writeln('  ${d.from} (${d.fromType.name}) -> ${d.bank}/${d.topic}');
      }
    }
    cli.out.add(buf.toString());

    // R4.2: the frame states the counts help used to apologise for
    // ("the naive number") — deleted from `description` above, restated
    // here as the fact it was standing in for.
    final resolvedAgainst = siblingTopics.isEmpty
        ? 'external links unjudged'
        : 'resolved against ${(siblingTopics.keys.toList()..sort()).join(', ')}';
    cli.diagnostics.add(
      'mem: health ${bank.name} — ${index.pages.length} pages, '
      '${health.orphans.length} orphans, ${judged.length} dead links, '
      '${unjudged.length} external unjudged; $resolvedAgainst\n',
    );
  }
}

/// `mem remember <topic> -t <type> -A <attention> [-f <path>] [--gist <s>] [--tag <t>]`
final class RememberCommand extends MemCommand {
  RememberCommand(super.cli) {
    argParser
      ..addOption('type', abbr: 't', valueHelp: 'mode')
      ..addOption('attention', abbr: 'A', valueHelp: 'A')
      ..addOption('file', abbr: 'f', valueHelp: 'path')
      ..addOption('gist', valueHelp: 's')
      ..addMultiOption('tag', valueHelp: 'tag')
      ..addFlag(
        'empty',
        negatable: false,
        help: 'Write a body of nothing. Without this, an empty body refuses '
            '— this write replaces a page whole, and an empty body on an '
            'existing topic reads the same as wiping it by accident.',
      );
  }

  @override
  String get name => 'remember';

  @override
  String get description => 'Create or replace a page whole.';

  @override
  List<String> get positionalLabels => const ['topic'];

  @override
  Future<void> run() async {
    final bank = resolveBank();
    if (bank == null) return;

    final topic = requirePositionals().first;

    final typeOpt = argResults!['type'] as String?;
    if (typeOpt == null) usageException('$name: -t <type> is required');
    final MemType type;
    try {
      type = MemType.parse(typeOpt);
    } on FormatException catch (e) {
      usageException('$name: ${e.message}');
    }

    final attentionOpt = argResults!['attention'] as String?;
    if (attentionOpt == null) usageException('$name: -A <attention> is required');
    final Attention attention;
    try {
      attention = Attention.parse(attentionOpt);
    } on FormatException catch (e) {
      usageException('$name: ${e.message}');
    }

    final body = await _readBody(this, cli);
    if (body == null) return;

    final writer = Writer(bank, actor: statedActor(), gist: cli.gistSource);
    final outcome = await writer.remember(
      topic,
      type: type,
      attention: attention,
      body: body,
      gist: argResults!['gist'] as String?,
      tags: (argResults!['tag'] as List<String>),
      allowEmpty: argResults!['empty'] as bool,
    );
    _reportOutcome(cli, bank.name, outcome);
  }
}

/// `mem refocus <topic> | <selectors> --to <A> | --by <±D>`
final class RefocusCommand extends MemCommand with SelectorArgs {
  RefocusCommand(super.cli) {
    declareSelectorFlags();
    argParser
      ..addOption('to', valueHelp: 'A')
      ..addOption(
        'attention',
        abbr: 'A',
        valueHelp: 'A',
        help: 'Alias for --to — remember\'s own flag, so a hand that just '
            'wrote a page does not have to switch vocabulary to move it.',
      )
      ..addOption('by', valueHelp: '±D');
  }

  @override
  String get name => 'refocus';

  @override
  String get description => 'Move attention alone — the body is never touched.';

  @override
  List<String> get positionalLabels => const ['topic'];

  @override
  int get minPositionals => 0;

  @override
  bool get repeating => true;

  @override
  Future<void> run() async {
    final bank = resolveBank();
    if (bank == null) return;

    if (_reportIfNoTree(cli, bank)) return;

    if (argResults!.wasParsed('to') && argResults!.wasParsed('attention')) {
      usageException('$name: --to and --attention/-A are the same flag — pass one');
    }
    final toOpt = (argResults!['to'] as String?) ?? (argResults!['attention'] as String?);
    final byOpt = argResults!['by'] as String?;
    if ((toOpt == null) == (byOpt == null)) {
      usageException(
        '$name: exactly one of --to <A>/--attention <A> or --by <±D> is required',
      );
    }

    final seenTopics = <String>{};
    final topics = [
      for (final t in requirePositionals())
        if (seenTopics.add(t)) t,
    ];
    final selector =
        topics.isEmpty ? buildSelector() : buildSelector(topics: topics.toSet());
    if (selector.select(bank.pages()).isEmpty) {
      cli.diagnostics.add(
        'mem: ${bank.name} — no pages under '
        '${reachDescription(topics: topics.isEmpty ? null : topics.toSet())}.\n',
      );
      cli.exitCode = 1;
      return;
    }

    final writer = Writer(bank, actor: statedActor());
    final outcome = await writer.refocus(
      selector,
      to: toOpt == null ? null : _parseAttention(toOpt),
      byTenths: byOpt == null ? null : _parseSignedTenths(byOpt),
    );
    _reportOutcome(cli, bank.name, outcome);
  }

  int _parseSignedTenths(String source) {
    final sign = source.startsWith('-') ? -1 : 1;
    final magnitude = source.replaceFirst(RegExp(r'^[+-]'), '');
    final value = double.tryParse(magnitude);
    if (value == null) usageException('$name: not a delta: $source');
    return sign * (value * 10).round();
  }
}

/// `mem tag <topic> | <selectors> --add <t> [--add <t> ...] --remove <t> [...]`
final class TagCommand extends MemCommand with SelectorArgs {
  TagCommand(super.cli) {
    declareSelectorFlags();
    argParser
      ..addMultiOption('add', valueHelp: 'tag')
      ..addMultiOption('remove', valueHelp: 'tag');
  }

  @override
  String get name => 'tag';

  @override
  String get description => 'Add or remove tags — the body and modified are never touched.';

  @override
  List<String> get positionalLabels => const ['topic'];

  @override
  int get minPositionals => 0;

  @override
  Future<void> run() async {
    final bank = resolveBank();
    if (bank == null) return;

    if (_reportIfNoTree(cli, bank)) return;

    final add = argResults!['add'] as List<String>;
    final remove = argResults!['remove'] as List<String>;
    if (add.isEmpty && remove.isEmpty) {
      usageException('$name: at least one of --add <tag> or --remove <tag> is required');
    }
    final overlap = add.toSet().intersection(remove.toSet());
    if (overlap.isNotEmpty) {
      usageException('$name: cannot --add and --remove the same tag: ${overlap.join(', ')}');
    }

    final topic = optionalPositional();
    final selector = buildSelector(topic: topic);
    if (selector.select(bank.pages()).isEmpty) {
      cli.diagnostics.add(
        'mem: ${bank.name} — no pages under ${reachDescription(topic: topic)}.\n',
      );
      cli.exitCode = 1;
      return;
    }

    final writer = Writer(bank, actor: statedActor());
    final outcome = await writer.tag(selector, add: add, remove: remove);
    _reportOutcome(cli, bank.name, outcome);
  }
}

/// `mem gist <topic> | <selectors> [--set <s>]`
final class GistCommand extends MemCommand with SelectorArgs {
  GistCommand(super.cli) {
    declareSelectorFlags();
    argParser.addOption('set', valueHelp: 's');
  }

  @override
  String get name => 'gist';

  @override
  String get description => 'Re-derive the cue in place — the body is never touched.';

  @override
  List<String> get positionalLabels => const ['topic'];

  @override
  int get minPositionals => 0;

  @override
  Future<void> run() async {
    final bank = resolveBank();
    if (bank == null) return;

    if (_reportIfNoTree(cli, bank)) return;

    final topic = optionalPositional();
    final selector = buildSelector(topic: topic);
    if (selector.select(bank.pages()).isEmpty) {
      cli.diagnostics.add(
        'mem: ${bank.name} — no pages under ${reachDescription(topic: topic)}.\n',
      );
      cli.exitCode = 1;
      return;
    }

    final writer = Writer(bank, actor: statedActor(), gist: cli.gistSource);
    final outcome = await writer.regist(selector, set: argResults!['set'] as String?);
    _reportOutcome(cli, bank.name, outcome);
  }
}

/// `mem forget <topic>...` — by name only, many at once. A selector must
/// never delete.
final class ForgetCommand extends MemCommand {
  ForgetCommand(super.cli);

  @override
  String get name => 'forget';

  @override
  String get description => 'Delete a page by topic. Content is deleted.';

  @override
  List<String> get positionalLabels => const ['topic'];

  @override
  bool get repeating => true;

  @override
  Future<void> run() async {
    final bank = resolveBank();
    if (bank == null) return;
    if (_reportIfNoTree(cli, bank)) return;

    final seen = <String>{};
    final topics = [
      for (final t in requirePositionals())
        if (seen.add(t)) t,
    ];

    // Checked before landing anything — [Draft.remove] no-ops on a name
    // that is not a page, so a report built from the act alone could not
    // tell a real deletion from a typo that changed nothing.
    final found = <String>[];
    final missing = <String>[];
    for (final topic in topics) {
      (bank.page(topic) == null ? missing : found).add(topic);
    }

    if (found.isEmpty) {
      cli.diagnostics.add(
        'mem: ${bank.name} — no page found for: ${missing.join(', ')}.\n',
      );
      cli.exitCode = 1;
      return;
    }

    final writer = Writer(bank, actor: statedActor());
    final outcome = await writer.forget(found);
    _reportOutcome(cli, bank.name, outcome);

    // A missing topic among a batch that landed something real is a
    // partial miss, not a failed call: named in full so a typo among many
    // topics is legible, but exit stays 0 — the caller asked for several
    // things and got some of them, same as `recall`'s partial miss.
    if (missing.isNotEmpty) {
      cli.diagnostics.add(
        'mem: ${bank.name} — no page found for: ${missing.join(', ')}.\n',
      );
    }
  }
}

/// `-f <path>`, or a true pipe on stdin — never an argument (R3.2). Both
/// reach the actual bytes through a seam [Mem] was handed, since a file read
/// is `dart:io` and this module may not touch it (only `bank.dart` may).
Future<String?> _readBody(MemCommand cmd, Mem cli) async {
  final filePath = cmd.argResults!['file'] as String?;
  if (filePath != null) {
    final reader = cli.fileReader;
    if (reader == null) {
      cmd.usageException('${cmd.name}: cannot read $filePath — no file access');
    }
    try {
      return await reader(filePath);
    } on Object catch (e) {
      cmd.usageException('${cmd.name}: could not read $filePath: $e');
    }
  }
  final reader = cli.stdinReader;
  if (reader == null) {
    cmd.usageException(
      '${cmd.name}: the body is required — pass -f <path> or pipe it on stdin',
    );
  }
  return reader();
}

/// The read path's own NO TREE — same diagnostic voice and the same exit
/// code as the write path's [NoTree] (see `LANDED, NO TREE` below), spelled
/// once so every read command that opens a single bank says it the same
/// way. **Deliberately not [Advance]/[NoTree] themselves**: those are the
/// vocabulary of bringing a tree up to the line a write just landed on, and
/// a read lands nothing — borrowing them would carry write vocabulary into
/// a layer that never writes.
///
/// The lie this guards against sits one level down, in [Bank.pages] and
/// [Bank.page]: both answer "nothing" whether the bank is genuinely empty or
/// its tree is simply not standing here. This is the cure at the consumer;
/// the source-level cure — making that distinction unrepresentable in
/// [Bank]'s own signature — is not this pass's to make.
///
/// Returns true when the bank has no tree, having already said why; the
/// caller's cue to stop rather than render "no pages" for what may in fact
/// be "no tree to read".
bool _reportIfNoTree(Mem cli, Bank bank) {
  if (bank.hasTree) return false;
  cli.diagnostics.add(
    'mem: ${bank.name} — NO TREE: no tree of this bank stands at '
    '${bank.materializationAddress.path}, so nothing is readable here. '
    'Materialize it.\n',
  );
  cli.exitCode = Mem.materializationLagCode;
  return true;
}

void _reportOutcome(Mem cli, String bankName, Outcome outcome) {
  switch (outcome) {
    case Written(:final topics, :final advance):
      cli.diagnostics.add('mem: $bankName — written ${topics.join(', ')}\n');
      // The act landed either way — the line carries it, and saying so is
      // honest. What must never happen is the *shape* of a clean write when
      // the tree a reader composes from was left behind: the failure that cost
      // us a session was not the stale tree, it was that nothing outside the
      // process could tell. So a tree that did not reach the line is named,
      // and the exit code carries it to whoever is not reading.
      switch (advance) {
        case Advanced():
          break;
        case Behind(:final blocking, :final report):
          cli.diagnostics.add(
            'mem: $bankName — LANDED, TREE STALE: the line carries the write '
            'and the working tree does not.\n',
          );
          // Either the account or the paths, never both. Where the primitive
          // has its own account, the paths are not a person's work standing in
          // anybody's way — a tree following a branch reports every page of
          // the write as staged, and naming those would accuse the reader of
          // blocking a write they never touched.
          if (report != null) {
            cli.diagnostics.add('mem: $bankName — $report\n');
          } else if (blocking.isNotEmpty) {
            cli.diagnostics.add(
              'mem: $bankName — standing in the way: ${blocking.join(', ')}\n',
            );
          }
          cli.exitCode = Mem.materializationLagCode;
        case NoTree(:final address):
          cli.diagnostics.add(
            'mem: $bankName — LANDED, NO TREE: the line carries the write and '
            'no tree of this bank stands at ${address.path}, so nothing is '
            'readable there. Materialize it.\n',
          );
          cli.exitCode = Mem.materializationLagCode;
      }
    case RefusedByGate(:final reason):
      cli.diagnostics.add('mem: refused — $reason\n');
      cli.exitCode = 1;
    case RefusedOnAssumedFields(:final topic, :final assumptions):
      cli.diagnostics.add(
        'mem: refused — $topic carries assumed fields '
        '(${assumptions.map((a) => a.field).join(', ')}); a write would '
        'canonize the guess\n',
      );
      cli.exitCode = 1;
    case RefusedOnHandEdit(:final topics):
      cli.diagnostics.add(
        'mem: refused — $bankName has hand-edited, uncommitted pages: '
        '${topics.join(', ')} — mem never reads them and the next write '
        'would silently overwrite them; commit or discard them with git '
        'first.\n',
      );
      cli.exitCode = 1;
    case RefusedOnEmptyBody(:final topic):
      cli.diagnostics.add(
        'mem: refused — $topic would write an empty body; pass --empty to '
        'write one on purpose.\n',
      );
      cli.exitCode = 1;
    case RefusedWithoutModel(:final topic):
      cli.diagnostics.add(
        'mem: refused — no gist for $topic (no model reachable — pass '
        '--gist or --set)\n',
      );
      cli.exitCode = 1;
  }
}

/// The account §2: one contiguous block, emitted after the artifact
/// (R2.4), every line prefixed `mem: ` (R2.5). Each render function below is
/// the one renderer over its verb's [Account] — R1.1's spine: the verb
/// computed the value, this reads it, nothing prints from inside the verb's
/// own logic.
String renderWalkFrame(WalkAccount a) {
  final buf = StringBuffer()
    ..writeln('mem: ${a.commandEcho} — ${a.weight.pages} pages, '
        '${a.weight.words} words, ${a.weight.links} links followed');

  if (a.notEntered > 0) {
    final byReason = a.notEnteredByReason;
    final parts = <String>[];
    void add(SkipReason reason, String label) {
      final n = byReason[reason];
      if (n != null && n > 0) parts.add('$n $label');
    }

    add(SkipReason.filtered, 'filtered (attention)');
    add(SkipReason.tooDeep, 'too deep');
    add(SkipReason.dead, 'dead');
    add(SkipReason.crossBank, 'cross-bank');
    add(SkipReason.bankNotFound, 'bank not found');
    buf.writeln('mem: ${a.notEntered} not entered — ${parts.join(', ')}');
  }

  for (final hint in evaluateHints(a, 'walk')) {
    buf.writeln('mem: $hint');
  }
  return buf.toString();
}

String renderSurveyFrame(SurveyAccount a) {
  final buf = StringBuffer();
  if (a.shown > 0) {
    buf.writeln('mem: survey ${a.bank} — ${a.shown} of ${a.totalInBank} '
        'shown, hottest first, ${a.words} words');
  } else {
    final suffix =
        a.filterDescription.isEmpty ? '' : ' (filter: ${a.filterDescription})';
    buf.writeln('mem: survey ${a.bank} — 0 of ${a.totalInBank} shown$suffix');
  }
  for (final hint in evaluateHints(a, 'survey')) {
    buf.writeln('mem: $hint');
  }
  return buf.toString();
}

String renderRecallFrame(RecallAccount a) {
  final buf = StringBuffer();
  if (a.requestedTopics.isNotEmpty) {
    if (a.foundCount == 0) {
      buf.writeln('mem: recall ${a.bank}/${a.requestedTopics.join(', ')} — no page.');
    } else {
      buf.writeln('mem: ${a.bank} — ${a.foundCount} pages, ${a.words} words');
    }
  } else if (a.foundCount == 0) {
    buf.writeln('mem: recall ${a.bank} — 0 of ${a.totalInBank} pages matched');
  } else {
    buf.writeln('mem: ${a.bank} — ${a.foundCount} pages, ${a.words} words');
  }
  for (final hint in evaluateHints(a, 'recall')) {
    buf.writeln('mem: $hint');
  }
  return buf.toString();
}

/// The call as understood, echoed back — entries in the order given, then
/// this verb's own flags as typed. Never the globals (`-b`, `-p`, `--age`,
/// `--actor`): the frame states what the walk did, not the whole argv.
String _walkCommandEcho(List<Address> entries, ArgResults args, {required bool shape}) {
  final parts = <String>['walk', for (final e in entries) e.toString()];

  const bands = ['hot', 'warm', 'cool', 'cold'];
  for (final band in bands) {
    if (args.wasParsed(band) && args[band] as bool) parts.add('--$band');
  }
  void addOpt(String flag) {
    final v = args[flag] as String?;
    if (v != null) parts.addAll(['--$flag', v]);
  }

  addOpt('min-attention');
  addOpt('max-attention');
  addOpt('type');
  addOpt('tag');
  addOpt('depth');
  if (args['cross-bank'] as bool) parts.add('--cross-bank');
  if (shape) parts.add('--shape');
  return parts.join(' ');
}

/// §6 `unreachable-hot`: computed only when [filter] admits attention 1.0 —
/// a filter that already excludes the hot band makes an unreached hot page
/// unremarkable, not a defect to name. Scoped to the entry banks' own hot
/// pages, since those are the ones an author who wrote this entry point
/// could actually have linked.
List<String> _hotUnreachable(
  String vantage,
  List<Address> entries,
  Selector? filter,
  Walked walked,
) {
  final max = filter?.maxAttention;
  if (max != null && max.tenths != Attention.maxTenths) return const [];

  final reachedByBank = <String, Set<String>>{};
  for (final r in walked.reached) {
    reachedByBank.putIfAbsent(r.address.bank, () => {}).add(r.address.topic);
  }

  final unreachable = <String>[];
  for (final bankName in {for (final e in entries) e.bank}) {
    final resolution = Bank.resolve(bankName, vantage: vantage);
    if (resolution is! Found || !resolution.bank.hasTree) continue;
    final reachedHere = reachedByBank[bankName] ?? const {};
    for (final page in Index.of(resolution.bank).pages) {
      if (page.fields.attention.tenths == Attention.maxTenths &&
          !reachedHere.contains(page.topic)) {
        unreachable.add(page.topic);
      }
    }
  }
  return unreachable;
}

/// R5.7: every response opens by naming the bank it answered from — the one
/// seam telling the kind's own book from a waking's when several are staged
/// at once. [SurveyCommand], [RecallCommand] and [HealthCommand] each answer
/// for exactly one, resolved by [MemCommand.resolveBank].
String _bankHeader(String name) => 'bank: $name\n\n';


const _surveyLegend = 'attention  topic — gist   #tags  ·modified  [words]';
const _surveyFooter = 'read full → mem recall <topic>';
const _rule = '─────────────────────────────────────────────────────────';

String _renderSurvey(
  List<Page> pages, {
  required AgeRender age,
  required bool truncated,
  required int from,
  required int to,
  required int total,
  required int threshold,
}) {
  final buf = StringBuffer()..writeln(_surveyLegend);
  if (truncated) {
    final line = 'showing $from–$to of $total, hottest first';
    buf.writeln(to < total ? '$line → mem survey --offset $to' : line);
  }
  buf.writeln();

  MemType? lastType;
  for (final page in pages) {
    final type = page.fields.type;
    if (type != lastType) {
      buf.writeln(type.name);
      lastType = type;
    }
    buf.writeln('  ${_cueLine(page, threshold, age)}');
  }
  buf
    ..writeln()
    ..write(_surveyFooter);
  return buf.toString();
}

String _cueLine(Page page, int threshold, AgeRender age) {
  final f = page.fields;
  final core = StringBuffer('${f.attention.render()}  ${page.topic}');
  if (f.gist != null && f.gist!.isNotEmpty) core.write(' — ${f.gist}');

  final cluster = <String>[];
  if (f.tags.isNotEmpty) cluster.add(f.tags.map((t) => '#$t').join(' '));
  final stated = _statedAge(f.modified, age);
  if (stated != null) cluster.add('·$stated');
  final words = _wordCount(page.body);
  if (words >= threshold) cluster.add('[${words}w]');
  if (f.assumptions.isNotEmpty) {
    cluster.add('⚠${f.assumptions.map((a) => a.field).join(',')}');
  }
  return cluster.isEmpty ? core.toString() : '$core  ${cluster.join('  ')}';
}

String _renderRecall(List<Page> pages, {required AgeRender age}) {
  final buf = StringBuffer();
  for (var i = 0; i < pages.length; i++) {
    if (i > 0) buf.writeln();
    final page = pages[i];
    buf
      ..writeln(_rule)
      ..writeln(_recallTitle(page, age));
    if (page.body.isNotEmpty) {
      buf
        ..writeln()
        ..writeln(page.body);
    }
  }
  return buf.toString();
}

/// The shaped form (R7.1, formerly `--dry-run`): the set a walk reaches, and
/// the set it does not — one line each, no bodies. What a composition spends
/// thousands of tokens saying, said in a page's worth, so the band can be
/// judged without being paid for.
///
/// The ring leads every line because the ring is the decision: a page enters
/// a waking mind by being linked from one already in the band, so *how far
/// out* it sits is the thing an author moves.
///
/// Carries no weight line and no not-entered count — both moved to the frame
/// (R7.3) — but the not-entered table itself stays: under `--shape` the
/// caller asked for the traversal, so the table is artifact, not account
/// (R3.2).
String _renderShape(Walked walked, {required String home}) {
  String label(Address address) =>
      address.bank == home ? address.topic : address.toString();

  final buf = StringBuffer()..writeln('ring   words  page  ← via');
  for (final reached in walked.reached) {
    final words = _wordCount(reached.page.body).toString().padLeft(6);
    final ring = reached.depth.toString().padLeft(4);
    final via = reached.from == null ? 'entry' : reached.from!;
    buf.writeln('$ring $words  ${label(reached.address)}  ← $via');
  }

  // A bank's own NO TREE is said once, per bank, on the diagnostic channel —
  // repeating those entries here would answer the same fact from two homes.
  final shown = [
    for (final skip in walked.skipped)
      if (skip.reason != SkipReason.noTree) skip,
  ];
  if (shown.isNotEmpty) {
    buf..writeln()..writeln('not entered');
    // One line per page: a page reached by several inbound links skips once
    // per edge in [walked.skipped], and a shaped walk answers what did not
    // enter and why — not how many citations it had. Grouped by address and
    // reason (not address alone) since the same page can genuinely skip for
    // different reasons on different paths — e.g. within depth on one edge,
    // past it on another — and folding those together would misreport why.
    final grouped = <String, (Address address, String reason, List<String> vias)>{};
    for (final skip in shown) {
      final via = skip.from == null ? 'entry' : skip.from!;
      final key = '${skip.address} ${skip.reason.name}';
      final entry = grouped.putIfAbsent(
        key,
        () => (skip.address, skip.reason.name, <String>[]),
      );
      if (!entry.$3.contains(via)) entry.$3.add(via);
    }
    for (final MapEntry(value: (address, reason, vias)) in grouped.entries) {
      buf.writeln('       $address  ← ${vias.join(', ')}  — $reason');
    }
  }
  return buf.toString();
}

/// A composed page is heavy from here up, and says its weight.
const _compositionHeavyWords = 400;

/// Ages a composition reports. Between them a page is neither news nor
/// suspect, and says nothing.
const _compositionFresh = Duration(hours: 24);
const _compositionStale = Duration(days: 90);

/// The composed form: pages fenced, flush left, and nothing else — no bank
/// banner, no ruler, no index. A walk renders a document to be read as one
/// mind, not a report about a traversal, so what frames a page is its own
/// address and only such vitals as are not the healthy state.
///
/// The address is bare inside [home] — the bank the walk was entered at — and
/// full (`mem://<bank>/<topic>`) for a page reached in any other. A single-bank
/// composition therefore carries no bank anywhere, while a crossed seam stays
/// visible on the page that crossed it.
String _renderComposition(
  List<Reached> reached, {
  required String home,
  required AgeRender age,
}) {
  final buf = StringBuffer();
  for (var i = 0; i < reached.length; i++) {
    if (i > 0) buf.writeln();
    final page = reached[i].page;
    final address = reached[i].address;
    final label = address.bank == home ? address.topic : address.toString();
    final vitals = _compositionVitals(page, age);
    buf.writeln('┌─ $label');
    if (page.body.isNotEmpty) buf.writeln(page.body);
    buf.writeln(vitals.isEmpty ? '└─ $label' : '└─ $label  ·  ${vitals.join('  ·  ')}');
  }
  return buf.toString();
}

/// Silence is the healthy state: a hot page of ordinary weight and ordinary
/// age, with nothing marked on it, closes on its address alone.
List<String> _compositionVitals(Page page, AgeRender age) {
  final f = page.fields;
  final vitals = <String>[];

  // The band, only when it is not hot — a composition is staged hot, so the
  // word appears exactly where a page runs cooler than its position claims.
  // `0.0` carries no band and is named for what it is, the vanishing point.
  final attention = f.attention;
  if (attention.tenths == Attention.minTenths) {
    vitals.add('a:${attention.render()}');
  } else if (attention.band != Band.hot) {
    vitals.add(attention.band.name);
  }

  final words = _wordCount(page.body);
  if (words >= _compositionHeavyWords) vitals.add('${words}w');

  // A stamp is stated unconditionally: the freshness gate below is itself
  // clock-derived — it drops a page's vital between two wakes with nothing in
  // the bank changed — so it lives only where the clock is already being read.
  // The cue it carried is not lost, it moves to the reader, who holds the
  // turn's own stamp and can do the arithmetic for free.
  final stated = _statedAge(f.modified, age);
  if (stated != null) {
    if (age != AgeRender.relative) {
      vitals.add(stated);
    } else {
      final since = DateTime.now().difference(f.modified!);
      if (since < _compositionFresh || since > _compositionStale) {
        vitals.add('$stated old');
      }
    }
  }

  if (f.tags.isNotEmpty) vitals.add(f.tags.map((t) => '#$t').join(' '));
  if (f.assumptions.isNotEmpty) {
    vitals.add('⚠assumed:${f.assumptions.map((a) => a.field).join(',')}');
  }
  return vitals;
}

String _recallTitle(Page page, AgeRender age) {
  final f = page.fields;
  final stated = _statedAge(f.modified, age);
  final parts = <String>[
    page.topic,
    f.type.name,
    'a:${f.attention.render()}',
    '${_wordCount(page.body)} words',
    if (stated != null)
      age == AgeRender.relative ? 'modified $stated ago' : 'modified $stated',
    if (f.assumptions.isNotEmpty)
      '⚠assumed:${f.assumptions.map((a) => a.field).join(',')}',
  ];
  return parts.join('  ·  ');
}

int _wordCount(String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) return 0;
  return trimmed.split(RegExp(r'\s+')).length;
}

/// What a page says about its age, or null when it says nothing — the one
/// place [AgeRender] is spent, and the only door to the clock in this file.
String? _statedAge(DateTime? modified, AgeRender age) => switch (age) {
      AgeRender.none => null,
      _ when modified == null => null,
      AgeRender.stamp => _stamp(modified),
      AgeRender.relative => _relativeAge(modified),
    };

/// The date, in UTC — stable across machines and across the clock, and it
/// moves only when the page does.
String _stamp(DateTime timestamp) {
  final t = timestamp.toUtc();
  final month = t.month.toString().padLeft(2, '0');
  final day = t.day.toString().padLeft(2, '0');
  return '${t.year}-$month-$day';
}

String _relativeAge(DateTime timestamp) {
  final d = DateTime.now().difference(timestamp);
  if (d.isNegative || d.inSeconds < 1) return 'now';
  if (d.inSeconds < 60) return '${d.inSeconds}s';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  return '${d.inDays}d';
}
