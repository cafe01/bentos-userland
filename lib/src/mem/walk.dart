import 'dart:collection';

import 'bank.dart';
import 'index.dart';
import 'page.dart';

/// A page named with its bank. The only form an entry point takes, and the
/// form every cross-bank link already has.
final class Address {
  const Address({required this.bank, required this.topic});

  final String bank;
  final String topic;

  static final _pattern = RegExp(r'^mem://([^/]+)/(.+)$');

  /// `mem://<bank>/<topic>`, and its parse. `null` for anything else.
  static Address? parse(String source) {
    final m = _pattern.firstMatch(source);
    if (m == null) return null;
    return Address(bank: m.group(1)!, topic: m.group(2)!);
  }

  @override
  String toString() => 'mem://$bank/$topic';

  @override
  bool operator ==(Object other) =>
      other is Address && other.bank == bank && other.topic == topic;

  @override
  int get hashCode => Object.hash(bank, topic);
}

/// Traversal from entry points: follows the links outward, level by level, in
/// the order the prose wrote them, and returns the pages in the order they
/// were reached. [The decomposition](../design-specification) and its
/// crossing laws govern.
///
/// **The walk walks the index.** Edges come from [Index.outbound], pages
/// come from the index it already holds, and a dead target is the index's
/// own answer. This component opens no file, parses no frontmatter and
/// reads no link itself — it decides where to go next and in what order.
final class Walk {
  Walk({
    required this.vantage,
    Index Function(Bank) open = Index.of,
    this.filter,
    this.depth,
  }) : _open = open;

  /// The vantage of the whole command. A bank met mid-walk resolves from
  /// this one and never from where the page that named it happens to live
  /// (R2.5).
  final String vantage;

  final Index Function(Bank) _open;

  /// The §5 selectors, applied as the walk goes: a page they exclude is not
  /// returned and its links are not followed (R6.3).
  final Selector? filter;

  /// How far the walk goes, in links followed. Null is unbounded.
  final int? depth;

  Future<Walked> from(List<Address> entries) async {
    final reached = <Reached>[];
    final skipped = <Skipped>[];
    final visited = <String>{};
    var linksFollowed = 0;

    final openIndexes = <String, Index>{};
    final byTopicOf = <String, Map<String, Page>>{};
    final unresolved = <String>{};

    final bankQueue = Queue<String>();
    final pending = <String, Queue<_Pending>>{};

    void enqueue(String bank, _Pending item) {
      final queue = pending.putIfAbsent(bank, () {
        bankQueue.add(bank);
        return Queue<_Pending>();
      });
      queue.add(item);
    }

    for (final entry in entries) {
      enqueue(entry.bank, _Pending(topic: entry.topic, depth: 0, from: null));
    }

    // One bank drained to exhaustion before the next begins (R6.4) — a
    // cross-bank edge discovered mid-drain lands in its target bank's own
    // queue and waits its turn rather than interleaving.
    while (bankQueue.isNotEmpty) {
      final bankName = bankQueue.removeFirst();
      // Stays live in [pending] while this bank drains, so a same-bank edge
      // discovered mid-drain (`enqueue` below) reaches this same queue
      // instead of `putIfAbsent` finding it gone and starting a new job.
      final queue = pending[bankName]!;

      var index = openIndexes[bankName];
      if (index == null && !unresolved.contains(bankName)) {
        final resolution = Bank.resolve(bankName, vantage: vantage);
        if (resolution is Found) {
          index = _open(resolution.bank);
          openIndexes[bankName] = index;
          byTopicOf[bankName] = {for (final p in index.pages) p.topic: p};
        } else {
          unresolved.add(bankName);
        }
      }

      if (index == null) {
        for (final item in queue) {
          skipped.add(Skipped(
            address: Address(bank: bankName, topic: item.topic),
            from: item.from,
            reason: SkipReason.bankNotFound,
          ));
        }
        pending.remove(bankName);
        continue;
      }

      final byTopic = byTopicOf[bankName]!;

      while (queue.isNotEmpty) {
        final item = queue.removeFirst();
        final key = '$bankName ${item.topic}';
        if (visited.contains(key)) continue;

        final address = Address(bank: bankName, topic: item.topic);

        if (depth != null && item.depth > depth!) {
          skipped.add(Skipped(address: address, from: item.from, reason: SkipReason.tooDeep));
          continue;
        }

        final page = byTopic[item.topic];
        if (page == null) {
          skipped.add(Skipped(address: address, from: item.from, reason: SkipReason.dead));
          continue;
        }

        if (filter != null && !filter!.matches(page)) {
          skipped.add(Skipped(address: address, from: item.from, reason: SkipReason.filtered));
          continue;
        }

        visited.add(key);
        reached.add(Reached(address: address, page: page));

        for (final edge in index.outbound(item.topic)) {
          linksFollowed++;
          enqueue(
            edge.bank ?? bankName,
            _Pending(topic: edge.topic, depth: item.depth + 1, from: item.topic),
          );
        }
      }
      pending.remove(bankName);
    }

    final words = reached.fold(0, (sum, r) => sum + _wordCount(r.page.body));
    return Walked(
      reached: reached,
      skipped: skipped,
      weight: Weight(pages: reached.length, words: words, links: linksFollowed),
    );
  }

  static int _wordCount(String body) =>
      body.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
}

final class _Pending {
  const _Pending({required this.topic, required this.depth, required this.from});
  final String topic;
  final int depth;
  final String? from;
}

/// A page and the address it was reached at. The bank is part of the answer:
/// a composition renders a foreign page by its full address, and only the walk
/// knows which bank a page came out of.
final class Reached {
  const Reached({required this.address, required this.page});

  final Address address;
  final Page page;
}

final class Walked {
  const Walked({required this.reached, required this.skipped, required this.weight});

  /// The pages in the order they were reached, each with its address. A page
  /// is returned once.
  final List<Reached> reached;

  /// The same pages, stripped of their banks — the reading a caller wants
  /// when it does not care where a page lives.
  List<Page> get pages => [for (final r in reached) r.page];

  /// What the walk did not follow, and why. Never silent — R6.7.
  final List<Skipped> skipped;

  /// Pages and words returned, and links **followed** — not links seen,
  /// which is the index's count and a different number.
  final Weight weight;
}

final class Skipped {
  const Skipped({required this.address, required this.from, required this.reason});

  final Address address;

  /// The topic whose link named [address]. `null` for a caller-supplied
  /// entry point — an absence, since no page in any bank named it.
  final String? from;
  final SkipReason reason;
}

enum SkipReason {
  /// The selector excluded it.
  filtered,

  /// Past the depth bound.
  tooDeep,

  /// No such page in its bank.
  dead,

  /// Its bank did not resolve from the vantage. The report says so and
  /// names the vantage; it never claims the bank is absent from the
  /// machine (R6.5).
  bankNotFound,
}
