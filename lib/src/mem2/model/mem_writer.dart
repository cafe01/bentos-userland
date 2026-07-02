import 'package:file/file.dart';

import 'attention.dart';
import 'mem_page.dart';

/// Atomic writes of a single page file. Two paths: a full body write that
/// stamps the organ's dates, and an attention-only rewrite that leaves the
/// body bytes and `modified` untouched. The clock is injected so date
/// behaviour is hermetically testable.
final class MemWriter {
  MemWriter(this.fs, this.now);

  final FileSystem fs;
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
  /// text so nothing outside the one line can drift.
  void refocus(File file, Attention attention) {
    final content = file.readAsStringSync();
    final rewritten = content.replaceFirst(
      RegExp(r'^attention:.*$', multiLine: true),
      'attention: ${attention.render()}',
    );
    _atomicWrite(file, rewritten);
  }

  void _atomicWrite(File file, String content) {
    file.parent.createSync(recursive: true);
    final tmp = fs.file('${file.path}.tmp');
    tmp.writeAsStringSync(content, flush: true);
    tmp.renameSync(file.path);
  }
}
