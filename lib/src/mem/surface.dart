import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../cli/positional_grammar.dart';
import '../git/model/actor.dart';
import 'attention.dart';
import 'bank.dart';
import 'index.dart';
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

  /// **0** — did what was asked, including an empty reach and a degraded
  /// read. **1** — a decided refusal, or a bank not found from the vantage.
  /// **2** — the call itself was invalid. **64** — nobody said who is writing.
  int exitCode = 0;

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
      diagnostics.add('${e.message}\n');
      exitCode = 2;
    }
    return exitCode;
  }
}

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

  Selector buildSelector({String? topic}) {
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
  String reachDescription({String? topic}) {
    if (topic != null) return topic;
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

    final selector = buildSelector();
    final index = Index.of(bank);
    final matched = index.select(selector);

    if (matched.isEmpty) {
      cli.diagnostics.add(
        'mem: ${bank.name} — no pages under ${reachDescription()}.\n',
      );
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
      truncated: offset > 0 || (limit != null && offset + limit < total),
      from: offset + 1,
      to: offset + sliced.length,
      total: total,
      threshold: threshold,
    ));

    final words = sliced.fold(0, (sum, p) => sum + _wordCount(p.body));
    cli.diagnostics.add(
      'mem: ${bank.name} — ${sliced.length} pages, $words words\n',
    );
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

    final index = Index.of(bank);
    final seenTopics = <String>{};
    final topics = [
      for (final t in requirePositionals())
        if (seenTopics.add(t)) t,
    ];

    if (topics.isEmpty) {
      final selector = buildSelector();
      final matched = index.select(selector);
      if (matched.isEmpty) {
        cli.diagnostics.add(
          'mem: ${bank.name} — no pages under ${reachDescription()}.\n',
        );
        return;
      }
      cli.out.add(_renderRecall(matched));
      final words = matched.fold(0, (sum, p) => sum + _wordCount(p.body));
      cli.diagnostics.add(
        'mem: ${bank.name} — ${matched.length} pages, $words words\n',
      );
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

    if (found.isEmpty) {
      cli.diagnostics.add(
        'mem: ${bank.name} — no pages under ${topics.join(', ')}.\n',
      );
      return;
    }

    cli.out.add(_renderRecall(found));
    final words = found.fold(0, (sum, p) => sum + _wordCount(p.body));
    cli.diagnostics.add(
      'mem: ${bank.name} — ${found.length} pages, $words words\n',
    );
    if (missing.isNotEmpty) {
      cli.diagnostics.add(
        'mem: ${bank.name} — no page found for: ${missing.join(', ')}.\n',
      );
    }
  }
}

/// `mem walk <mem://bank/topic>... [<selectors>] [--depth <n>]`
final class WalkCommand extends MemCommand with SelectorArgs {
  WalkCommand(super.cli) {
    declareSelectorFlags();
    argParser.addOption('depth', valueHelp: 'n');
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

    final walk = Walk(
      vantage: vantage,
      filter: hasSelector ? buildSelector() : null,
      depth: depthOpt == null ? null : int.parse(depthOpt),
    );
    final walked = await walk.from(entries);

    if (walked.reached.isEmpty) {
      cli.diagnostics.add(
        'mem: no pages reached from ${entries.map((e) => e.toString()).join(', ')}.\n',
      );
    } else {
      cli.out.add(_renderComposition(walked.reached, home: entries.first.bank));
    }

    cli.diagnostics.add(
      'mem: ${walked.weight.pages} pages, ${walked.weight.words} words, '
      '${walked.weight.links} links followed\n',
    );
    for (final skip in walked.skipped) {
      final origin = skip.from == null ? 'entry point' : 'from ${skip.from}';
      cli.diagnostics.add(
        'mem: skipped ${skip.address} ($origin) — ${skip.reason.name}\n',
      );
    }
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
      'Bare, this counts every type together, journals included — the '
      'naive number. Pass --type to read one type at a time; summed over '
      'every type but autobiographical, that is the real defect count.';

  @override
  List<String> get positionalLabels => const ['topic'];

  @override
  int get minPositionals => 0;

  @override
  Future<void> run() async {
    final bank = resolveBank();
    if (bank == null) return;
    cli.out.add(_bankHeader(bank.name));

    final index = Index.of(bank);
    final topic = optionalPositional();

    cli.diagnostics.add(
      'mem: ${bank.name} — health, this bank alone; external links unjudged.\n',
    );

    if (topic != null) {
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

    final hasSelector = ['hot', 'warm', 'cool', 'cold', 'min-attention',
            'max-attention', 'type', 'tag']
        .any((f) => argResults!.wasParsed(f));
    final health = index.health(within: hasSelector ? buildSelector() : null);

    final buf = StringBuffer()
      ..writeln('orphans (${health.orphans.length}):');
    for (final t in health.orphans) {
      buf.writeln('  $t');
    }
    buf.writeln('dead links (${health.dead.length}):');
    for (final d in health.dead) {
      final target = d.bank == null ? d.topic : '${d.bank}/${d.topic}';
      final note = d.foundIn == null ? '' : ' (found in ${d.foundIn})';
      buf.writeln('  ${d.from} (${d.fromType.name}) -> $target [${d.kind.name}]$note');
    }
    cli.out.add(buf.toString());
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
      ..addMultiOption('tag', valueHelp: 'tag');
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
  Future<void> run() async {
    final bank = resolveBank();
    if (bank == null) return;

    final toOpt = argResults!['to'] as String?;
    final byOpt = argResults!['by'] as String?;
    if ((toOpt == null) == (byOpt == null)) {
      usageException('$name: exactly one of --to <A> or --by <±D> is required');
    }

    final topic = optionalPositional();
    final selector = buildSelector(topic: topic);
    if (selector.select(bank.pages()).isEmpty) {
      cli.diagnostics.add(
        'mem: ${bank.name} — no pages under ${reachDescription(topic: topic)}.\n',
      );
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

    final topic = optionalPositional();
    final selector = buildSelector(topic: topic);
    if (selector.select(bank.pages()).isEmpty) {
      cli.diagnostics.add(
        'mem: ${bank.name} — no pages under ${reachDescription(topic: topic)}.\n',
      );
      return;
    }

    final writer = Writer(bank, actor: statedActor(), gist: cli.gistSource);
    final outcome = await writer.regist(selector, set: argResults!['set'] as String?);
    _reportOutcome(cli, bank.name, outcome);
  }
}

/// `mem forget <topic>` — by name only. A selector must never delete.
final class ForgetCommand extends MemCommand {
  ForgetCommand(super.cli);

  @override
  String get name => 'forget';

  @override
  String get description => 'Delete a page by topic. Content is deleted.';

  @override
  List<String> get positionalLabels => const ['topic'];

  @override
  Future<void> run() async {
    final bank = resolveBank();
    if (bank == null) return;

    final topic = requirePositionals().first;

    final writer = Writer(bank, actor: statedActor());
    final outcome = await writer.forget(topic);
    _reportOutcome(cli, bank.name, outcome);
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
          cli.exitCode = 1;
        case NoTree(:final address):
          cli.diagnostics.add(
            'mem: $bankName — LANDED, NO TREE: the line carries the write and '
            'no tree of this bank stands at ${address.path}, so nothing is '
            'readable there. Materialize it.\n',
          );
          cli.exitCode = 1;
      }
    case RefusedByGate(:final reason):
      cli.diagnostics.add('mem: refused — $reason\n');
      cli.exitCode = 1;
    case RefusedAsContested(:final attempts):
      cli.diagnostics.add('mem: refused — contested after $attempts attempts\n');
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
        'mem: refused — hand-edited and uncommitted: ${topics.join(', ')}\n',
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
    buf.writeln('  ${_cueLine(page, threshold)}');
  }
  buf
    ..writeln()
    ..write(_surveyFooter);
  return buf.toString();
}

String _cueLine(Page page, int threshold) {
  final f = page.fields;
  final core = StringBuffer('${f.attention.render()}  ${page.topic}');
  if (f.gist != null && f.gist!.isNotEmpty) core.write(' — ${f.gist}');

  final cluster = <String>[];
  if (f.tags.isNotEmpty) cluster.add(f.tags.map((t) => '#$t').join(' '));
  if (f.modified != null) cluster.add('·${_relativeAge(f.modified!)}');
  final words = _wordCount(page.body);
  if (words >= threshold) cluster.add('[${words}w]');
  if (f.assumptions.isNotEmpty) {
    cluster.add('⚠${f.assumptions.map((a) => a.field).join(',')}');
  }
  return cluster.isEmpty ? core.toString() : '$core  ${cluster.join('  ')}';
}

String _renderRecall(List<Page> pages) {
  final buf = StringBuffer();
  for (var i = 0; i < pages.length; i++) {
    if (i > 0) buf.writeln();
    final page = pages[i];
    buf
      ..writeln(_rule)
      ..writeln(_recallTitle(page));
    if (page.body.isNotEmpty) {
      buf
        ..writeln()
        ..writeln(page.body);
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
String _renderComposition(List<Reached> reached, {required String home}) {
  final buf = StringBuffer();
  for (var i = 0; i < reached.length; i++) {
    if (i > 0) buf.writeln();
    final page = reached[i].page;
    final address = reached[i].address;
    final label = address.bank == home ? address.topic : address.toString();
    final vitals = _compositionVitals(page);
    buf.writeln('┌─ $label');
    if (page.body.isNotEmpty) buf.writeln(page.body);
    buf.writeln(vitals.isEmpty ? '└─ $label' : '└─ $label  ·  ${vitals.join('  ·  ')}');
  }
  return buf.toString();
}

/// Silence is the healthy state: a hot page of ordinary weight and ordinary
/// age, with nothing marked on it, closes on its address alone.
List<String> _compositionVitals(Page page) {
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

  final modified = f.modified;
  if (modified != null) {
    final age = DateTime.now().difference(modified);
    if (age < _compositionFresh || age > _compositionStale) {
      vitals.add('${_relativeAge(modified)} old');
    }
  }

  if (f.tags.isNotEmpty) vitals.add(f.tags.map((t) => '#$t').join(' '));
  if (f.assumptions.isNotEmpty) {
    vitals.add('⚠assumed:${f.assumptions.map((a) => a.field).join(',')}');
  }
  return vitals;
}

String _recallTitle(Page page) {
  final f = page.fields;
  final parts = <String>[
    page.topic,
    f.type.name,
    'a:${f.attention.render()}',
    '${_wordCount(page.body)} words',
    if (f.modified != null) 'modified ${_relativeAge(f.modified!)} ago',
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

String _relativeAge(DateTime timestamp) {
  final d = DateTime.now().difference(timestamp);
  if (d.isNegative || d.inSeconds < 1) return 'now';
  if (d.inSeconds < 60) return '${d.inSeconds}s';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  return '${d.inDays}d';
}
