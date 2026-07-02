import 'package:file/file.dart';

import '../place/model/place.dart';
import 'model/attention.dart';
import 'model/mem_page.dart';
import 'model/mem_writer.dart';

/// The memory-tree gateway — the only mem component that touches the Place API
/// or the filesystem tree. It resolves stores via `memoryRoot`, reads and
/// writes page files at topic paths, runs the cascade over ancestors
/// (nearest-wins shadowing, origin-annotated), and resolves the write target.
/// No other component constructs a path string or climbs the tree.
final class MemStore {
  MemStore({
    required this.vantage,
    required this.entity,
    required this.fs,
    required this.writer,
  });

  /// The vantage place — where the cascade starts and new topics land.
  final Place vantage;
  final String entity;
  final FileSystem fs;
  final MemWriter writer;

  /// The vantage and its ancestors, nearest-first — the ordered climb the
  /// cascade walks.
  List<Place> get _chain => [vantage, ...vantage.ancestors];

  File _pageFile(Place place, String topic) =>
      fs.file(fs.path.join(place.memoryRoot(entity).path, '$topic.md'));

  /// The page at [topic] in [place], or null if absent. Annotated with origin.
  MemPage? readAt(Place place, String topic) {
    final file = _pageFile(place, topic);
    if (!file.existsSync()) return null;
    return MemPage.parse(topic, file.readAsStringSync()).withOrigin(place);
  }

  /// Every page under [place]'s store, origin-annotated. A nested topic keeps
  /// its slash-path. Empty when the store does not exist.
  List<MemPage> listAt(Place place) {
    final root = place.memoryRoot(entity);
    if (!root.existsSync()) return const [];
    final pages = <MemPage>[];
    for (final e in root.listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.md')) continue;
      final topic = fs.path
          .withoutExtension(fs.path.relative(e.path, from: root.path))
          .replaceAll(r'\', '/');
      pages.add(MemPage.parse(topic, e.readAsStringSync()).withOrigin(place));
    }
    return pages;
  }

  /// The merged view: the vantage's pages plus every ancestor's, nearest place
  /// winning on a shared topic (the shadowed ancestor suppressed). Each page
  /// carries the place it came from.
  List<MemPage> cascade() {
    final seen = <String>{};
    final merged = <MemPage>[];
    for (final place in _chain) {
      for (final page in listAt(place)) {
        if (seen.add(page.topic)) merged.add(page);
      }
    }
    return merged;
  }

  /// The place a write to [topic] lands: the resolved page's home place when
  /// the topic already exists somewhere on the chain, else the vantage (only
  /// creation anchors).
  Place writeTargetFor(String topic) {
    for (final place in _chain) {
      if (_pageFile(place, topic).existsSync()) return place;
    }
    return vantage;
  }

  /// Write a body to [topic] at its resolved target, returning the landed page
  /// annotated with that place.
  MemPage write(
    String topic, {
    required MemType type,
    required Attention attention,
    List<String> tags = const [],
    String? gist,
    required String body,
  }) {
    final target = writeTargetFor(topic);
    final page = writer.writeBody(
      _pageFile(target, topic),
      topic,
      type: type,
      attention: attention,
      tags: tags,
      gist: gist,
      body: body,
    );
    return page.withOrigin(target);
  }
}
