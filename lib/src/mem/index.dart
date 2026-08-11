import 'bank.dart';
import 'page.dart';

/// One bank read into memory: every page parsed, every link read from prose,
/// held as one value for the life of a command — the answer to both the
/// selector queries of §5 and the health questions of §4.5.
///
/// **Nothing here touches the floor.** An [Index] is built from a [Bank]'s
/// already-read [pages] and is otherwise pure, which is what makes it
/// testable against a handful of pages with no repository anywhere.
final class Index {
  Index._(this.bank, this.pages, this._byTopic, this._outbound);

  /// One pass over [bank]: every page read once, every link read from its
  /// body once. Computed per command and held for its life — nothing is
  /// materialized and nothing is cached across invocations (R4.4, R4.6).
  factory Index.of(Bank bank) {
    final pages = bank.pages();
    final byTopic = {for (final page in pages) page.topic: page};
    final outbound = {
      for (final page in pages)
        page.topic: [
          for (final link in page.links)
            Edge(from: page.topic, bank: link.bank, topic: link.topic, order: link.order),
        ],
    };
    return Index._(bank, pages, byTopic, outbound);
  }

  final Bank bank;
  final List<Page> pages;
  final Map<String, Page> _byTopic;
  final Map<String, List<Edge>> _outbound;

  /// Its own weight, so a caller never measures the value to know what it got.
  Weight get weight {
    var words = 0;
    var links = 0;
    for (final page in pages) {
      words += _wordCount(page.body);
      links += _outbound[page.topic]?.length ?? 0;
    }
    return Weight(pages: pages.length, words: words, links: links);
  }

  List<Page> select(Selector selector) => selector.select(pages);

  /// The links [topic]'s page writes, in prose order. Empty for a topic
  /// this index never read.
  List<Edge> outbound(String topic) => _outbound[topic] ?? const [];

  /// The links to [topic] **written in this bank** — R4.1.0. A link written
  /// in another bank lives in that bank's own index and nowhere else.
  List<Edge> inbound(String topic) => [
        for (final edges in _outbound.values)
          for (final edge in edges)
            if (edge.bank == null && edge.topic == topic) edge,
      ];

  /// [siblingTopics] is knowledge, never a reach: the topic sets of banks
  /// this *command* already holds, keyed by bank name, supplied by the
  /// caller that resolved them (walk, surface) — an [Index] built alone
  /// never goes looking for another bank. Omitted, every internal dead link
  /// reads [DeadKind.missing] and every external link goes unjudged, exactly
  /// as little as this bank alone can honestly know.
  Health health({Selector? within, Map<String, Set<String>>? siblingTopics}) {
    final asked = [...within == null ? pages : within.select(pages)]
      ..sort((a, b) => a.topic.compareTo(b.topic));

    final dead = <DeadLink>[
      for (final page in asked)
        for (final edge in outbound(page.topic))
          if (_classify(edge, siblingTopics) case final found?)
            DeadLink(
              from: page.topic,
              fromType: page.fields.type,
              bank: edge.bank,
              topic: edge.topic,
              kind: found.kind,
              foundIn: found.foundIn,
            ),
    ];

    final orphans = [
      for (final page in asked)
        if (inbound(page.topic).isEmpty) page.topic,
    ];

    return Health(
      scope: Scope(bank: bank.name, within: within),
      dead: dead,
      orphans: orphans,
    );
  }

  /// `null` means the edge is not dead — its topic exists where it claims to.
  ({DeadKind kind, String? foundIn})? _classify(
    Edge edge,
    Map<String, Set<String>>? siblingTopics,
  ) {
    if (edge.bank == null) {
      if (_byTopic.containsKey(edge.topic)) return null;
      if (siblingTopics != null) {
        for (final sibling in siblingTopics.keys.toList()..sort()) {
          if (siblingTopics[sibling]!.contains(edge.topic)) {
            return (kind: DeadKind.elsewhere, foundIn: sibling);
          }
        }
      }
      return (kind: DeadKind.missing, foundIn: null);
    }

    if (siblingTopics == null) return null; // external, unjudged
    final topics = siblingTopics[edge.bank];
    if (topics == null) return (kind: DeadKind.bankNotFound, foundIn: null);
    if (topics.contains(edge.topic)) return null;
    return (kind: DeadKind.missing, foundIn: null);
  }

  static int _wordCount(String body) =>
      body.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
}

/// A link between two topics, in the order it was written.
final class Edge {
  const Edge({required this.from, this.bank, required this.topic, required this.order});

  final String from;

  /// The bank named by the address; null for an edge inside this bank.
  final String? bank;
  final String topic;

  /// Position among the writing page's links, in prose order.
  final int order;
}

/// What a [Health] answer is true of. It rides the value and is printed with
/// it, so an orphan count can never be read without knowing what counted.
final class Scope {
  const Scope({required this.bank, this.within});

  /// Always same-bank, and stated rather than assumed.
  final String bank;
  final Selector? within;
}

final class Health {
  const Health({required this.scope, required this.dead, required this.orphans});

  final Scope scope;
  final List<DeadLink> dead;

  /// Pages with no inbound edge in this bank.
  final List<String> orphans;
}

final class DeadLink {
  const DeadLink({
    required this.from,
    required this.fromType,
    this.bank,
    required this.topic,
    required this.kind,
    this.foundIn,
  });

  final String from;

  /// The type of the page that wrote it — R4.3's separation, made here and
  /// reported side by side: a page that records history names pages
  /// forgotten after the day it was written, and repairing those would
  /// falsify the record.
  final MemType fromType;

  /// The bank the link named; null for an internal link.
  final String? bank;
  final String topic;
  final DeadKind kind;

  /// For [DeadKind.elsewhere], the sibling bank that actually holds [topic].
  /// Null otherwise.
  final String? foundIn;
}

enum DeadKind {
  /// No page of that topic in this bank, and none in any sibling bank the
  /// caller supplied.
  missing,

  /// An internal link — no bank stated — whose topic exists in a sibling
  /// bank the caller supplied: an address written without its bank, and
  /// repairable, never a missing page.
  elsewhere,

  /// An address whose bank was not among the siblings the caller supplied.
  /// What was observed is where the caller looked, never that the bank is
  /// absent from the machine.
  bankNotFound,
}

final class Weight {
  const Weight({required this.pages, required this.words, required this.links});

  final int pages;
  final int words;
  final int links;
}
