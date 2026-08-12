import '../entity/action.dart' as ent;
import '../git/model/actor.dart';
import 'attention.dart';
import 'bank.dart';
import 'page.dart';

/// The model seam. Gist derivation is the one capability the tool cannot
/// perform itself, so it is an interface, injected, whose absence is an
/// ordinary refusal: a write with no [GistSource] behaves exactly as one
/// whose derivation came back empty.
abstract interface class GistSource {
  /// Null when no line could be derived. Never throws for an unavailable
  /// model, and never invents a cue for a body it could not read.
  Future<String?> derive(String body);
}

/// The write path entire: build the page, derive the gist through the model
/// seam, land the act, absorb a contested landing, bring the tree to the
/// line, refuse what must be refused.
final class Writer {
  Writer(this._bank, {Actor? actor, GistSource? gist, this.attempts = 3})
      : _actor = actor,
        _gist = gist;

  final Bank _bank;
  final Actor? _actor;
  final GistSource? _gist;

  /// How many times a [Contested] landing is retried before it is reported
  /// as [RefusedAsContested]. Never applies to [Barred] — retrying a bar is
  /// an infinite loop wearing a retry policy.
  final int attempts;

  /// Creates or replaces a page whole. The gist is derived through the model
  /// seam unless [gist] is given, in which case the seam is never called.
  Future<Outcome> remember(
    String topic, {
    required MemType type,
    required Attention attention,
    required String body,
    String? gist,
    List<String>? tags,
  }) async {
    final String cue;
    if (gist != null) {
      cue = gist;
    } else {
      final derived = await _gist?.derive(body);
      if (derived == null) return RefusedWithoutModel(topic);
      cue = derived;
    }

    final existing = _bank.page(topic);
    final stamp = DateTime.now().toUtc();
    final page = Page(
      topic: topic,
      fields: Fields(
        type: type,
        attention: attention,
        tags: tags ?? const [],
        created: existing?.fields.created ?? stamp,
        modified: stamp,
        gist: cue,
      ),
      body: body,
    );

    return _land(
      topics: [topic],
      say: 'remember $topic',
      build: (draft) => draft.write(page),
    );
  }

  /// Attention alone, on one page or a whole selected set. The body is not
  /// touched and `modified` does not move — it is metadata, not a
  /// modification. Refuses on any selected page whose frontmatter was
  /// itself guessed (R7.2): rewriting it would canonize the guess.
  Future<Outcome> refocus(Selector selector, {Attention? to, int? byTenths}) async {
    final pages = selector.select(_bank.pages());
    final assumed = _firstAssumed(pages);
    if (assumed != null) {
      return RefusedOnAssumedFields(assumed.topic, assumed.fields.assumptions);
    }

    final rewritten = [
      for (final page in pages)
        Page(
          topic: page.topic,
          fields: page.fields.copyWith(
            attention: _resolve(page.fields.attention, to, byTenths),
          ),
          body: page.body,
        ),
    ];

    return _land(
      topics: [for (final p in rewritten) p.topic],
      say: 'refocus ${rewritten.map((p) => p.topic).join(', ')}',
      build: (draft) {
        for (final p in rewritten) {
          draft.write(p);
        }
      },
    );
  }

  /// Re-derives the cue in place from the body already stored, or sets it to
  /// [set] verbatim. Refuses where a selected page's body is hand-edited and
  /// uncommitted (R3.11) — a derived write must never describe a version of
  /// the page nobody is reading — or where its frontmatter was guessed
  /// (R7.2).
  Future<Outcome> regist(Selector selector, {String? set}) async {
    final pages = selector.select(_bank.pages());

    final dirty = _bank.handEdited.toSet();
    final blocked = [for (final p in pages) if (dirty.contains(p.topic)) p.topic];
    if (blocked.isNotEmpty) return RefusedOnHandEdit(blocked);

    final assumed = _firstAssumed(pages);
    if (assumed != null) {
      return RefusedOnAssumedFields(assumed.topic, assumed.fields.assumptions);
    }

    final rewritten = <Page>[];
    for (final page in pages) {
      final String cue;
      if (set != null) {
        cue = set;
      } else {
        final derived = await _gist?.derive(page.body);
        if (derived == null) return RefusedWithoutModel(page.topic);
        cue = derived;
      }
      rewritten.add(Page(
        topic: page.topic,
        fields: page.fields.copyWith(gist: cue),
        body: page.body,
      ));
    }

    return _land(
      topics: [for (final p in rewritten) p.topic],
      say: 'gist ${rewritten.map((p) => p.topic).join(', ')}',
      build: (draft) {
        for (final p in rewritten) {
          draft.write(p);
        }
      },
    );
  }

  /// By topic name only. A selector must never delete.
  Future<Outcome> forget(String topic) => _land(
        topics: [topic],
        say: 'forget $topic',
        build: (draft) => draft.remove(topic),
      );

  Page? _firstAssumed(List<Page> pages) {
    for (final page in pages) {
      if (page.isAssumed) return page;
    }
    return null;
  }

  Attention _resolve(Attention current, Attention? to, int? byTenths) {
    if (to != null) return to;
    final tenths = (current.tenths + (byTenths ?? 0))
        .clamp(Attention.minTenths, Attention.maxTenths);
    return Attention(tenths / 10);
  }

  /// Lands one act, absorbing a contested tip up to [attempts] times before
  /// reporting [RefusedAsContested]. [build] runs once, ahead of the loop —
  /// a decision, not an oversight: retrying re-attempts the swap against a
  /// fresh tip, never the selection or the derivation that produced [build]
  /// in the first place. A page contested out from under this call therefore
  /// lands with the field values this call read before the retry, not a
  /// fresher one — bounded by [attempts], and resolved for good on the
  /// caller's next invocation, which reads the tree fresh from the top.
  Future<Outcome> _land({
    required List<String> topics,
    required void Function(Draft) build,
    required String say,
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      final landing = await _bank.land('page', build, actor: _actor, say: say);
      switch (landing) {
        case Landed(:final action):
          return Written(topics: topics, action: action, advance: _bank.advance());
        case Barred(:final reason):
          return RefusedByGate(reason);
        case Contested():
          continue;
      }
    }
    return RefusedAsContested(attempts);
  }
}

sealed class Outcome {
  const Outcome();
}

final class Written extends Outcome {
  const Written({required this.topics, required this.action, required this.advance});

  final List<String> topics;
  final ent.Action action;
  final Advance advance;
}

sealed class Refused extends Outcome {
  const Refused();
}

/// A gate refused. Retrying is an infinite loop wearing a retry policy — the
/// same act is refused again.
final class RefusedByGate extends Refused {
  const RefusedByGate(this.reason);
  final String reason;
}

/// The tip moved underneath the act for [attempts] tries running. A caller
/// may try again; nothing was decided.
final class RefusedAsContested extends Refused {
  const RefusedAsContested(this.attempts);
  final int attempts;
}

/// A selected page carries fields this parse had to assume, and a write
/// would canonize the guess.
final class RefusedOnAssumedFields extends Refused {
  const RefusedOnAssumedFields(this.topic, this.assumptions);
  final String topic;
  final List<FieldAssumption> assumptions;
}

/// A selected page's file holds uncommitted changes, so a cue derived from
/// the stored body would describe prose nobody is reading.
final class RefusedOnHandEdit extends Refused {
  const RefusedOnHandEdit(this.topics);
  final List<String> topics;
}

/// No model, and no gist supplied — for a verb whose whole output is the
/// cue.
final class RefusedWithoutModel extends Refused {
  const RefusedWithoutModel(this.topic);
  final String topic;
}
