import 'dart:io';

import 'attention.dart';
import 'mem_page.dart';

/// Atomic writes of a single page file. Three paths: a full body write that
/// stamps the organ's dates, an attention-only rewrite, and a gist-only
/// rewrite — the latter two leaving the body bytes and `modified` untouched.
/// The clock is injected so date behaviour is hermetically testable.
final class MemWriter {
  MemWriter(this.now);

  final DateTime Function() now;

  /// Create or replace [file] with a body write. `created` is stamped once (on
  /// first write, or carried from the existing file); `modified` is refreshed
  /// on every body write. Returns the landed page.
  MemPage writeBody(
    File file,
    String topic, {
    required MemType type,
    required Attention attention,
    List<String> tags = const [],
    String? gist,
    required String body,
  }) {
    final stamp = now();
    DateTime created = stamp;
    if (file.existsSync()) {
      final existing = MemPage.parse(topic, file.readAsStringSync());
      created = existing.fields.created ?? stamp;
    }
    final page = MemPage(
      topic: topic,
      fields: FrontmatterFields(
        type: type,
        attention: attention,
        tags: tags,
        created: created,
        modified: stamp,
        gist: gist,
      ),
      body: body,
    );
    _atomicWrite(file, page.serialize());
    return page;
  }

  /// Attention-only rewrite: replace the `attention:` line in place, leaving
  /// every other byte — body and `modified` — identical. Operates on the raw
  /// text so nothing outside the one line can drift. A page whose attention
  /// was never a legible line (assumed on read, `--to` is the one caller that
  /// may still reach it) has no line to replace — falls back to a structural
  /// rewrite that introduces the key, the same way [regist] must for a gist.
  void refocus(File file, String topic, Attention attention) {
    final content = file.readAsStringSync();
    final pattern = RegExp(r'^attention:.*$', multiLine: true);
    if (pattern.hasMatch(content)) {
      _atomicWrite(file, content.replaceFirst(pattern, 'attention: ${attention.render()}'));
      return;
    }
    final page = MemPage.parse(topic, content);
    final rewritten = MemPage(
      topic: topic,
      fields: page.fields.copyWith(attention: attention),
      body: page.body,
    );
    _atomicWrite(file, rewritten.serialize());
  }

  /// Gist-only rewrite: the page's `gist` replaced, every other field — body,
  /// `created`, `modified`, tags, extras — carried through as parsed. Returns
  /// the landed page.
  ///
  /// Structural, where [refocus] is textual, because the gist has two shapes a
  /// line replacement cannot reach: it may be **absent** (no line to replace,
  /// and appending textually means re-deriving the schema order here), and a
  /// hand-written page may carry a **multi-line** YAML scalar (`>`, `|`, or a
  /// wrapped quoted string), where replacing the first line leaves the
  /// continuation behind as body-level garbage that no longer parses. The price
  /// is that a hand-edited page comes back normalized to the organ's own
  /// serialization; a page the organ wrote is byte-identical but for the gist.
  MemPage regist(File file, String topic, String gist) {
    final page = MemPage.parse(topic, file.readAsStringSync());
    final rewritten = MemPage(
      topic: topic,
      fields: page.fields.copyWith(gist: gist),
      body: page.body,
    );
    _atomicWrite(file, rewritten.serialize());
    return rewritten;
  }

  void _atomicWrite(File file, String content) {
    file.parent.createSync(recursive: true);
    final tmp = File('${file.path}.tmp');
    tmp.writeAsStringSync(content, flush: true);
    tmp.renameSync(file.path);
  }
}
