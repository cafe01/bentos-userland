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
/// `unresolved-topic` and `no-match` are wired for the verbs that compute an
/// [Account] today — `recall` and `survey`; `refocus`/`tag`/`gist`/`forget`
/// keep their plainer existing diagnostic until they too compute one.
final List<HintRule> hintRules = <HintRule>[
  HintRule(
    id: 'unresolved-topic',
    verbs: {'recall'},
    fires: (o) => o is RecallAccount && o.missingTopics.isNotEmpty,
    render: (o) {
      final r = o as RecallAccount;
      // One topic named: the common case, and the one the contract's own
      // worked example states. Several named and only some missing: the
      // first missing one carries the hint — a second hint slot is spent
      // elsewhere before a second missing topic would get its own line.
      final topic = r.missingTopics.first;
      final nearest = nearestNames(topic, r.bankTopics);
      final suggestion = nearest.isEmpty ? '' : ' Nearest by name: ${nearest.join(', ')}.';
      return 'no page at $topic in ${r.bank}.$suggestion `mem survey` for the index.';
    },
  ),
  HintRule(
    id: 'no-match',
    verbs: {'survey', 'recall'},
    fires: (o) => switch (o) {
      SurveyAccount(:final shown, :final totalInBank) => shown == 0 && totalInBank > 0,
      RecallAccount(:final requestedTopics, :final foundCount, :final totalInBank) =>
        requestedTopics.isEmpty && foundCount == 0 && totalInBank > 0,
      _ => false,
    },
    render: (o) {
      final total = switch (o) {
        SurveyAccount(:final totalInBank) => totalInBank,
        RecallAccount(:final totalInBank) => totalInBank,
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
