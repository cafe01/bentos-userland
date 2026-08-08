import 'package:yaml/yaml.dart';

import '../../place/place.dart';
import 'attention.dart';

/// The memory modes, in composition order — the order every merged view and
/// selector output preserves.
enum MemType {
  autobiographical,
  episodic,
  semantic,
  procedural,
  prospective;

  /// Parse the mode name, case- and whitespace-insensitive (`Semantic`,
  /// ` semantic `) — the emitted form is exact-lowercase, but a hand-edited
  /// page reads by intent, not by byte.
  static MemType parse(String source) {
    final normalized = source.trim().toLowerCase();
    return MemType.values.firstWhere(
      (t) => t.name == normalized,
      orElse: () => throw FormatException('unknown mem type: "$source"'),
    );
  }
}

/// One field the parser could not read as authored, with what was assumed in
/// its place. Structured rather than a free string so a reader can act on
/// [field] (mark a survey line, refuse a write) while [reason] carries the
/// prose for the stderr line a human reads.
final class FieldAssumption {
  const FieldAssumption(this.field, this.reason);

  final String field;
  final String reason;

  @override
  String toString() => '$field: $reason';
}

/// The small, deliberate frontmatter key set of a memory page. `type` is the
/// one required key (OKF's mode); the rest ride as clean extensions. Unknown
/// keys are preserved verbatim (the OKF augmentation guard).
final class FrontmatterFields {
  const FrontmatterFields({
    required this.type,
    required this.attention,
    this.tags = const [],
    this.created,
    this.modified,
    this.gist,
    this.extras = const {},
    this.assumptions = const [],
  });

  final MemType type;
  final Attention attention;
  final List<String> tags;
  final DateTime? created;
  final DateTime? modified;
  final String? gist;

  /// Unknown keys, carried through untouched so an augmented page never loses
  /// data on rewrite.
  final Map<String, Object?> extras;

  /// Fields this parse could not read as authored and had to guess — empty
  /// for a clean page. Never serialized: it describes how these fields were
  /// obtained, not a value of the page itself.
  final List<FieldAssumption> assumptions;

  static const _known = {'type', 'attention', 'tags', 'created', 'modified', 'gist'};

  /// Parse a frontmatter YAML map — total, never throws. `type` and
  /// `attention` are the schema floor, but a page is knowledge before it is a
  /// schema: a missing or off-grammar field degrades to a guessed default,
  /// named in [assumptions], rather than taking the whole page down. [doc]
  /// null means no frontmatter could be read at all (absent, unterminated, or
  /// unparseable YAML) — everything is assumed.
  static FrontmatterFields parse(YamlMap? doc) {
    final assumptions = <FieldAssumption>[];

    if (doc == null) {
      assumptions.add(const FieldAssumption(
        'frontmatter',
        'missing or unreadable — type and attention assumed',
      ));
      return FrontmatterFields(
        type: MemType.semantic,
        attention: Attention.assumedDefault,
        assumptions: assumptions,
      );
    }

    final rawType = doc['type'];
    MemType type;
    if (rawType is String) {
      try {
        type = MemType.parse(rawType);
      } on FormatException {
        assumptions.add(FieldAssumption('type', 'unrecognized ("$rawType") — assumed semantic'));
        type = MemType.semantic;
      }
    } else {
      assumptions.add(FieldAssumption(
        'type',
        rawType == null ? 'missing — assumed semantic' : 'not a string — assumed semantic',
      ));
      type = MemType.semantic;
    }

    final rawAttention = doc['attention'];
    Attention attention;
    if (rawAttention == null) {
      assumptions.add(const FieldAssumption('attention', 'missing — assumed 0.5'));
      attention = Attention.assumedDefault;
    } else {
      try {
        attention = Attention.parse(rawAttention.toString());
      } on FormatException {
        assumptions.add(FieldAssumption('attention', 'off-notch ("$rawAttention") — assumed 0.5'));
        attention = Attention.assumedDefault;
      }
    }

    return FrontmatterFields(
      type: type,
      attention: attention,
      tags: _toStringList(doc['tags']),
      created: _toDate(doc['created'], 'created', assumptions),
      modified: _toDate(doc['modified'], 'modified', assumptions),
      gist: doc['gist']?.toString(),
      assumptions: assumptions,
      extras: {
        for (final e in doc.nodes.entries)
          if (!_known.contains(e.key.toString()))
            e.key.toString(): e.value.value,
      },
    );
  }

  /// Serialize to a frontmatter block (with `---` fences), keys in schema
  /// order, extras trailing.
  String serialize() {
    final buf = StringBuffer('---\n')
      ..writeln('type: ${type.name}')
      ..writeln('attention: ${attention.render()}');
    if (tags.isNotEmpty) buf.writeln('tags: [${tags.join(', ')}]');
    if (created != null) buf.writeln('created: ${created!.toIso8601String()}');
    if (modified != null) buf.writeln('modified: ${modified!.toIso8601String()}');
    if (gist != null) buf.writeln('gist: ${_quoted(gist!)}');
    extras.forEach((k, v) => buf.writeln('$k: ${_preserved(v?.toString() ?? '')}'));
    buf.write('---');
    return buf.toString();
  }

  FrontmatterFields copyWith({
    MemType? type,
    Attention? attention,
    List<String>? tags,
    DateTime? created,
    DateTime? modified,
    String? gist,
  }) => FrontmatterFields(
        type: type ?? this.type,
        attention: attention ?? this.attention,
        tags: tags ?? this.tags,
        created: created ?? this.created,
        modified: modified ?? this.modified,
        gist: gist ?? this.gist,
        extras: extras,
      );

  /// A list, or a bare scalar taken as its one-element list — a tag written
  /// by hand as `tags: solo` rather than `tags: [solo]` is still one tag.
  static List<String> _toStringList(Object? v) {
    if (v is YamlList) return [for (final e in v) e.toString()];
    if (v is String && v.trim().isNotEmpty) return [v.trim()];
    return const [];
  }

  /// A date, or null with an [assumptions] entry — never a throw. There is no
  /// honest guess for a date that failed to parse, so the field is dropped
  /// rather than fabricated.
  static DateTime? _toDate(Object? v, String field, List<FieldAssumption> assumptions) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString().trim());
    } on FormatException {
      assumptions.add(FieldAssumption(field, 'unparseable ("$v") — dropped'));
      return null;
    }
  }

  /// The gist is written as a quoted scalar, unconditionally.
  ///
  /// It is prose the writer never sees, and read as YAML structure it is
  /// live ammunition: a leading indicator (`*`, `&`, `-`, …) comes back as an
  /// alias or a list, a bare `true`/`3` as a bool or a number, an embedded
  /// `: ` as a nested map. One such page does not merely lose its own gist —
  /// `remember` walks the whole bank before writing, so the unreadable page
  /// freezes *every* write to that bank, including the one that would repair it.
  ///
  /// Quoting conditionally would mean a predicate deciding, per value, whether
  /// YAML can be trusted with it — and that predicate is one more thing to get
  /// wrong, silently, at the exact moment nothing can be written any more. The
  /// cost of always quoting is a pair of quotes in the file.
  static String _quoted(String v) =>
      '"${v.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n')}"';

  /// An unknown key's value, kept as close to how it arrived as this writer can
  /// manage — the OKF augmentation guard. Here the predicate stays, and for a
  /// reason the gist does not share: an extra is *somebody else's* value of
  /// unknown type, so quoting a bare `3` or `true` would silently retype their
  /// number as a string on every rewrite. The gist is ours and always prose,
  /// which is exactly why it can be quoted without asking.
  static String _preserved(String v) => _isBare(v) ? v : _quoted(v);

  static const _indicators = {'-', '?', ':', ',', '[', ']', '{', '}', '#', '&', '*', '!', '|', '>', "'", '"', '%', '@', '`'};

  static bool _isBare(String v) =>
      v.isNotEmpty &&
      v.trim() == v &&
      !_indicators.contains(v[0]) &&
      !v.contains(': ') &&
      !v.contains(' #') &&
      !v.contains('\n') &&
      !v.endsWith(':');
}

/// One memory page: a single markdown file — frontmatter plus body — addressed
/// by a slash-topic that *is* its path. Its [origin] place is set by the
/// cascade so a merged view can name where an inherited page lives.
final class MemPage {
  const MemPage({
    required this.topic,
    required this.fields,
    required this.body,
    this.origin,
  });

  final String topic;
  final FrontmatterFields fields;
  final String body;

  /// The place this page was read from; null until the cascade annotates it.
  final Place? origin;

  /// Parse a page file's [content] for the given [topic] — total, never
  /// throws. A file is still a page even when its header is not: no opening
  /// fence, no closing fence, or a header that is not valid YAML all degrade
  /// to a bodyless-frontmatter page carrying the entire content as prose,
  /// with [FrontmatterFields.assumptions] naming what could not be trusted.
  /// The only thing that still throws here is nothing — a read that fails
  /// outright (file not found, an I/O error) is the caller's concern, above
  /// this parse.
  static MemPage parse(String topic, String content) {
    if (!content.startsWith('---')) {
      return MemPage(topic: topic, fields: FrontmatterFields.parse(null), body: content.trim());
    }
    final close = content.indexOf('\n---', 3);
    if (close == -1) {
      return MemPage(topic: topic, fields: FrontmatterFields.parse(null), body: content.trim());
    }

    final yamlStr = content.substring(3, close).trim();
    YamlMap? doc;
    try {
      final loaded = loadYaml(yamlStr);
      if (loaded is YamlMap) doc = loaded;
    } on Object {
      doc = null;
    }

    final bodyStart = close + 4;
    final body = bodyStart < content.length
        ? content
            .substring(bodyStart)
            .replaceFirst(RegExp(r'^\n+'), '')
            .replaceFirst(RegExp(r'\n+$'), '')
        : '';

    return MemPage(topic: topic, fields: FrontmatterFields.parse(doc), body: body);
  }

  /// Full file content: frontmatter block then body.
  String serialize() {
    final fm = fields.serialize();
    return body.isEmpty ? '$fm\n' : '$fm\n\n$body\n';
  }

  MemPage withOrigin(Place place) =>
      MemPage(topic: topic, fields: fields, body: body, origin: place);

  /// Whether this read had to guess at least one field — the fact a caller
  /// checks before printing, marking, or laundering it into a write.
  bool get isDegraded => fields.assumptions.isNotEmpty;

  /// The disclosure item 3 of the parser brief requires: a guess is never
  /// allowed to look authored. One line, the page named, every assumption
  /// spelled out — never only "something was wrong".
  String describeDegradation() {
    final where = origin != null ? ' (${origin!.name})' : '';
    return 'mem: degraded page $topic$where: ${fields.assumptions.join('; ')}';
  }
}
