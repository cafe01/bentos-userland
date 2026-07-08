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

  static MemType parse(String source) => MemType.values.firstWhere(
        (t) => t.name == source,
        orElse: () => throw FormatException('unknown mem type: "$source"'),
      );
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

  static const _known = {'type', 'attention', 'tags', 'created', 'modified', 'gist'};

  /// Parse a frontmatter YAML map. A missing/invalid `type` or `attention` is
  /// an error — those two are the schema floor.
  static FrontmatterFields parse(YamlMap doc) {
    final type = doc['type'];
    if (type is! String) throw const FormatException('frontmatter missing required `type`');
    final attention = doc['attention'];
    if (attention == null) throw const FormatException('frontmatter missing required `attention`');

    return FrontmatterFields(
      type: MemType.parse(type),
      attention: Attention.parse(attention.toString()),
      tags: _toStringList(doc['tags']),
      created: _toDate(doc['created']),
      modified: _toDate(doc['modified']),
      gist: doc['gist']?.toString(),
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
    if (gist != null) buf.writeln('gist: ${_scalar(gist!)}');
    extras.forEach((k, v) => buf.writeln('$k: ${_scalar(v?.toString() ?? '')}'));
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

  static List<String> _toStringList(Object? v) {
    if (v is YamlList) return [for (final e in v) e.toString()];
    return const [];
  }

  static DateTime? _toDate(Object? v) => v == null ? null : DateTime.parse(v.toString());

  static String _scalar(String v) =>
      v.contains(': ') || v.contains(' #') || v.startsWith('"') ? '"${v.replaceAll('"', '\\"')}"' : v;
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

  /// Parse a page file's [content] for the given [topic]. No frontmatter block
  /// is an error — every page is self-describing.
  static MemPage parse(String topic, String content) {
    if (!content.startsWith('---')) {
      throw FormatException('page "$topic" has no frontmatter');
    }
    final close = content.indexOf('\n---', 3);
    if (close == -1) throw FormatException('page "$topic" frontmatter unterminated');

    final yamlStr = content.substring(3, close).trim();
    final doc = loadYaml(yamlStr);
    if (doc is! YamlMap) throw FormatException('page "$topic" frontmatter is not a map');

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
}
