import 'index.dart';
import 'nearest.dart';
import 'walk.dart';

/// What a verb computed, before anything is said about it: the facts a
/// caller would budget or act against, held with no I/O and no clock (§1,
/// R1.3). Two renderers read the same value — the frame, always, and the
/// hints, conditionally — so a verb's `run()` computes one of these and
/// hands it to a renderer; it never prints as it goes (R1.1). Not the same
/// thing as `Writer`'s own `Outcome` (`written`/`refused`), which answers a
/// different question — what a write landed as, not what a read reports.
/// See `output-contract.md`.
sealed class Account {
  const Account();

  /// The bank the answer came from — R5.7, restated here because a hint
  /// speaks in the bank's name too.
  String get bank;
}

final class WalkAccount extends Account {
  const WalkAccount({
    required this.bank,
    required this.commandEcho,
    required this.reached,
    required this.skipped,
    required this.weight,
    required this.hotUnreachable,
  });

  @override
  final String bank;

  /// The call as the caller meant it — entries and the verb's own flags,
  /// echoed back exactly as `output-contract.md` §8 shows it. Never the raw
  /// argv: the globals (`-b`, `-p`, `--age`, `--actor`) are not this verb's
  /// business to repeat.
  final String commandEcho;

  final List<Reached> reached;
  final List<Skipped> skipped;
  final Weight weight;

  /// Topics, hot in their own bank, that this walk did not reach — computed
  /// only when the filter admits attention 1.0 (§6 `unreachable-hot`). Empty
  /// when the rule does not apply, not merely when nothing qualifies.
  final List<String> hotUnreachable;

  /// A bank's own NO TREE has already been said elsewhere (§6, unchanged) —
  /// counting it again here would answer the same fact from two homes.
  Iterable<Skipped> get _countable => skipped.where((s) => s.reason != SkipReason.noTree);

  int get notEntered => _countable.length;

  Map<SkipReason, int> get notEnteredByReason {
    final counts = <SkipReason, int>{};
    for (final skip in _countable) {
      counts[skip.reason] = (counts[skip.reason] ?? 0) + 1;
    }
    return counts;
  }

  List<({String from, Address target})> get deadLinks => [
        for (final skip in skipped)
          if (skip.reason == SkipReason.dead)
            (from: skip.from ?? 'entry point', target: skip.address),
      ];
}

final class SurveyAccount extends Account {
  const SurveyAccount({
    required this.bank,
    required this.shown,
    required this.totalInBank,
    required this.filterDescription,
    required this.words,
  });

  @override
  final String bank;

  /// Pages actually printed — after `--limit`/`--offset`, so this is the
  /// artifact's own count and not the filter's match count.
  final int shown;

  /// Every page the bank holds, filter or no filter — the number a caller
  /// budgets an empty result against (§8.4: the bank's size survives a
  /// filter that matched nothing).
  final int totalInBank;

  /// The selector as typed (`--tag craft --cold`), or empty for none.
  final String filterDescription;

  final int words;
}

final class RecallAccount extends Account {
  const RecallAccount({
    required this.bank,
    required this.requestedTopics,
    required this.foundCount,
    required this.missingTopics,
    required this.totalInBank,
    required this.filterDescription,
    required this.words,
    required this.bankTopics,
  });

  @override
  final String bank;

  /// Topics named on the command line, in the order they were typed. Empty
  /// when recall was called with selectors instead (`recall --hot`).
  final List<String> requestedTopics;

  final int foundCount;
  final List<String> missingTopics;
  final int totalInBank;
  final String filterDescription;
  final int words;

  /// Every topic this bank holds — the candidate pool `unresolved-topic`
  /// ranks against.
  final List<String> bankTopics;
}

/// The account for the four verbs with a selection step before they write —
/// `refocus`, `tag`, `gist`, `forget`. Mirrors [RecallAccount]'s found/missing
/// split so `unresolved-topic` and `no-match` answer them without a new rule
/// shape (§6). [changed] and [unchanged] split what matched further: a page
/// whose new value is the value it already held never reaches the writer
/// (§1 — this fires in ordinary use, so it is frame, not a hint, R2.3).
final class WriteAccount extends Account {
  const WriteAccount({
    required this.bank,
    required this.verb,
    required this.requestedTopics,
    required this.missingTopics,
    required this.changed,
    required this.unchanged,
    required this.totalInBank,
    required this.filterDescription,
    required this.bankTopics,
  });

  @override
  final String bank;

  /// `refocus`, `tag`, `gist` or `forget` — one [Account] shape, one renderer
  /// (`_reportWrite` in `surface.dart`), named per call so the same shape
  /// answers for all four.
  final String verb;

  /// Topics named on the command line, in order. Empty when the verb was
  /// called with selectors instead.
  final List<String> requestedTopics;

  final List<String> missingTopics;

  /// Topics actually landed — a value that differed from what the page
  /// already held.
  final List<String> changed;

  /// Topics matched and asked for, but already holding the value asked —
  /// no write was attempted for these.
  final List<String> unchanged;

  final int totalInBank;
  final String filterDescription;

  /// Every topic this bank holds — the candidate pool `unresolved-topic`
  /// ranks against.
  final List<String> bankTopics;

  int get foundCount => changed.length + unchanged.length;
}

/// A rule, evaluated over an [Account] a verb already computed. `fires` is
/// pure — no file reads, no clock, no ambient state (R5.1). Registry order
/// is priority (R5.2); a caller stops at the first two matches (R2.2).
final class HintRule {
  const HintRule({
    required this.id,
    required this.verbs,
    required this.fires,
    required this.render,
  });

  final String id;
  final Set<String> verbs;
  final bool Function(Account outcome) fires;
  final String Function(Account outcome) render;
}

/// The first cut, §6 — in registry order. `unknown-option` and `no-tree` are
/// not here: the first fires before any verb computes an [Account] at all
/// (in the argument-parsing failure path, per §6's own note), and the
/// second is the existing NO TREE message, left unchanged by name (§6).
/// `unresolved-topic` and `no-match` answer both [RecallAccount] and
/// [WriteAccount] — one rule, not one per verb (§6's own note: this is the
/// rule that does not get cut, or duplicated). `no-match` leaves `forget`
/// out: it has no selector, so its only miss shape is a named topic absent,
/// already `unresolved-topic`'s.
final List<HintRule> hintRules = <HintRule>[
  HintRule(
    id: 'unresolved-topic',
    verbs: {'recall', 'refocus', 'tag', 'gist', 'forget'},
    fires: (o) => switch (o) {
      RecallAccount(:final missingTopics) => missingTopics.isNotEmpty,
      WriteAccount(:final missingTopics) => missingTopics.isNotEmpty,
      _ => false,
    },
    render: (o) {
      final (missingTopics, bank, bankTopics) = switch (o) {
        RecallAccount(:final missingTopics, :final bank, :final bankTopics) =>
          (missingTopics, bank, bankTopics),
        WriteAccount(:final missingTopics, :final bank, :final bankTopics) =>
          (missingTopics, bank, bankTopics),
        _ => const (<String>[], '', <String>[]),
      };
      // One topic named: the common case, and the one the contract's own
      // worked example states. Several named and only some missing: the
      // first missing one carries the hint — a second hint slot is spent
      // elsewhere before a second missing topic would get its own line.
      final topic = missingTopics.first;
      final nearest = nearestNames(topic, bankTopics);
      final suggestion = nearest.isEmpty ? '' : ' Nearest by name: ${nearest.join(', ')}.';
      return 'no page at $topic in $bank.$suggestion `mem survey` for the index.';
    },
  ),
  HintRule(
    id: 'no-match',
    verbs: {'survey', 'recall', 'refocus', 'tag', 'gist'},
    fires: (o) => switch (o) {
      SurveyAccount(:final shown, :final totalInBank) => shown == 0 && totalInBank > 0,
      RecallAccount(:final requestedTopics, :final foundCount, :final totalInBank) =>
        requestedTopics.isEmpty && foundCount == 0 && totalInBank > 0,
      WriteAccount(:final requestedTopics, :final foundCount, :final totalInBank) =>
        requestedTopics.isEmpty && foundCount == 0 && totalInBank > 0,
      _ => false,
    },
    render: (o) {
      final total = switch (o) {
        SurveyAccount(:final totalInBank) => totalInBank,
        RecallAccount(:final totalInBank) => totalInBank,
        WriteAccount(:final totalInBank) => totalInBank,
        _ => 0,
      };
      return 'no page matches. ${o.bank} has $total pages; `mem survey` lists them, hottest first.';
    },
  ),
  HintRule(
    id: 'dead-link',
    verbs: {'walk'},
    fires: (o) => o is WalkAccount && o.deadLinks.isNotEmpty,
    render: (o) {
      final w = o as WalkAccount;
      final n = w.deadLinks.length;
      String label(Address a) => a.bank == w.bank ? a.topic : a.toString();
      final list = w.deadLinks.map((d) => '${d.from} → ${label(d.target)}').join(', ');
      return '$n link${n == 1 ? '' : 's'} point at pages that do not exist: $list. '
          '`mem health` lists every one.';
    },
  ),
  HintRule(
    id: 'unreachable-hot',
    verbs: {'walk'},
    fires: (o) => o is WalkAccount && o.hotUnreachable.isNotEmpty,
    render: (o) {
      final w = o as WalkAccount;
      final n = w.hotUnreachable.length;
      final verb = n == 1 ? 'is' : 'are';
      final noun = n == 1 ? 'page' : 'pages';
      return '$n hot $noun $verb unreachable from this entry: ${w.hotUnreachable.join(', ')}. '
          'Heat is not passage — a hot page nobody links never stages.';
    },
  ),
];

/// Registry order, first two matches win (R5.2, R2.2).
List<String> evaluateHints(Account outcome, String verb) {
  final lines = <String>[];
  for (final rule in hintRules) {
    if (lines.length >= 2) break;
    if (!rule.verbs.contains(verb)) continue;
    if (rule.fires(outcome)) lines.add(rule.render(outcome));
  }
  return lines;
}
