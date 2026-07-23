import 'dart:io';

import 'package:bentos_userland/src/mem2/model/attention.dart';
import 'package:bentos_userland/src/mem2/model/mem_page.dart';
import 'package:bentos_userland/src/place/place.dart';
import 'package:path/path.dart' as p;

/// Build a bare [MemPage] for pure-component tests — no filesystem.
MemPage memPage(
  String topic, {
  MemType type = MemType.semantic,
  String attention = '0.5',
  List<String> tags = const [],
  String gist = '',
  String body = 'body',
  DateTime? modified,
  Place? origin,
}) =>
    MemPage(
      topic: topic,
      fields: FrontmatterFields(
        type: type,
        attention: Attention.parse(attention),
        tags: tags,
        gist: gist.isEmpty ? null : gist,
        modified: modified,
      ),
      body: body,
      origin: origin,
    );

/// A memory habitat: helpers to mark places and seed page files through bare
/// `dart:io`. Constructed *inside* `runInMemoryFs`, where every call lands on
/// the hermetic in-memory filesystem — the successor of the old
/// `MemoryFileSystem`-injected habitat.
final class MemHabitat {
  MemHabitat({this.bank = 'john'});

  final String bank;

  /// A fixed clock — deterministic dates.
  static final clock = DateTime.utc(2026, 7, 2, 10);
  DateTime now() => clock;

  /// Mark [dirPath] as a place.
  void place(String dirPath) {
    Directory(p.join(dirPath, '.place')).createSync(recursive: true);
  }

  /// Seed a raw page file at [topic] under [placePath]'s store for [bank] —
  /// the on-disk layout contract, spelled out on purpose.
  void seed(String placePath, String topic, String content) {
    final file = File(p.join(placePath, '$bank.mem', '$topic.md'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  /// A minimal valid page body for [topic] at [attention].
  static String page(String type, String attention, String body) =>
      '---\ntype: $type\nattention: $attention\n---\n\n$body\n';
}
