import 'package:bentos_userland/src/mem2/model/attention.dart';
import 'package:bentos_userland/src/mem2/model/mem_page.dart';
import 'package:bentos_userland/src/place/model/place.dart';
import 'package:bentos_userland/src/place/place_resolver.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';

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

/// A hermetic memory habitat: a MemoryFileSystem with an injected home and a
/// [PlaceResolver], plus helpers to mark places and seed page files.
final class MemHabitat {
  MemHabitat({this.home = '/home/john', this.entity = 'john'}) {
    fs.directory(home).createSync(recursive: true);
    resolver = PlaceResolver(fs: fs, home: home);
  }

  final FileSystem fs = MemoryFileSystem();
  final String home;
  final String entity;
  late final PlaceResolver resolver;

  /// A fixed clock — deterministic dates.
  static final clock = DateTime.utc(2026, 7, 2, 10);
  DateTime now() => clock;

  /// Mark [dirPath] as a place.
  void place(String dirPath) {
    fs.directory(dirPath).createSync(recursive: true);
    fs.directory(fs.path.join(dirPath, '.place')).createSync(recursive: true);
  }

  /// Seed a raw page file at [topic] under [placePath]'s store for [entity].
  void seed(String placePath, String topic, String content) {
    final file = fs.file(
      fs.path.join(placePath, '.place', 'mem', entity, '$topic.md'),
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  /// A minimal valid page body for [topic] at [attention].
  static String page(String type, String attention, String body) =>
      '---\ntype: $type\nattention: $attention\n---\n\n$body\n';
}
