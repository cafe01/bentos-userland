import 'package:yaml/yaml.dart';

/// Structured frontmatter fields for a memory page content file.
final class FrontmatterFields {
  const FrontmatterFields({
    this.telos,
    this.gist,
    this.links,
    this.tags,
  });

  final String? telos;
  final String? gist;
  final List<String>? links;
  final List<String>? tags;

  bool get isEmpty => telos == null && gist == null && links == null && tags == null;

  /// Parse frontmatter from page content.
  ///
  /// Returns `(fields, body)`. If no valid frontmatter block, returns empty
  /// fields and the full [content] as body.
  static (FrontmatterFields, String) parse(String content) {
    if (!content.startsWith('---')) return (const FrontmatterFields(), content);
    final closeIdx = content.indexOf('\n---', 3);
    if (closeIdx == -1) return (const FrontmatterFields(), content);

    final yamlStr = content.substring(3, closeIdx).trim();
    final bodyStart = closeIdx + 5;
    final body = bodyStart < content.length
        ? content.substring(bodyStart).replaceFirst(RegExp(r'^\n'), '')
        : '';

    YamlMap? doc;
    try {
      final parsed = loadYaml(yamlStr);
      if (parsed is YamlMap) doc = parsed;
    } on YamlException {
      return (const FrontmatterFields(), content);
    }
    if (doc == null) return (const FrontmatterFields(), content);

    return (
      FrontmatterFields(
        telos: doc['telos'] as String?,
        gist: doc['gist'] as String?,
        links: _toStringList(doc['links']),
        tags: _toStringList(doc['tags']),
      ),
      body,
    );
  }

  static List<String>? _toStringList(dynamic value) {
    if (value == null) return null;
    if (value is YamlList) return [for (final v in value) v.toString()];
    return null;
  }

  FrontmatterFields merge(FrontmatterFields overlay) => FrontmatterFields(
        telos: overlay.telos ?? telos,
        gist: overlay.gist ?? gist,
        links: overlay.links ?? links,
        tags: overlay.tags ?? tags,
      );

  String serialize() {
    if (isEmpty) return '';
    final buf = StringBuffer('---\n');
    if (telos != null) buf.writeln('telos: ${_scalar(telos!)}');
    if (gist != null) buf.writeln('gist: ${_scalar(gist!)}');
    if (links != null && links!.isNotEmpty) {
      buf.writeln('links:');
      for (final l in links!) { buf.writeln('  - $l'); }
    }
    if (tags != null && tags!.isNotEmpty) {
      buf.writeln('tags:');
      for (final t in tags!) { buf.writeln('  - $t'); }
    }
    buf.write('---');
    return buf.toString();
  }

  String applyTo(String body) {
    final fm = serialize();
    if (fm.isEmpty) return body;
    return body.isNotEmpty ? '$fm\n\n$body' : '$fm\n';
  }

  static String _scalar(String value) {
    if (_needsQuoting(value)) {
      final escaped = value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
      return '"$escaped"';
    }
    return value;
  }

  static bool _needsQuoting(String value) {
    if (value.isEmpty) return true;
    final first = value[0];
    if ('|>@`!%{[&*?'.contains(first)) return true;
    if (value.contains(': ')) return true;
    if (value.endsWith(':')) return true;
    if (value.contains(' #')) return true;
    final lower = value.toLowerCase();
    return ['true', 'false', 'null', 'yes', 'no', 'on', 'off'].contains(lower);
  }
}
