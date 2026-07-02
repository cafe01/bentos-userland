import 'package:args/args.dart';

import '../band.dart';
import '../model/attention.dart';
import '../model/mem_page.dart';
import '../page_selector.dart';

/// The shared *reach* — the predicate options survey, recall, and refocus all
/// accept, and their resolution into [PageSelector] arguments. One definition,
/// three callers: the read side's picking mechanism.
final class Reach {
  const Reach({this.minAttention, this.maxAttention, this.type, this.tag});

  final Attention? minAttention;
  final Attention? maxAttention;
  final MemType? type;
  final String? tag;

  /// True when any predicate narrows the set — distinguishes a bare command
  /// from a predicate-driven one.
  bool get isEmpty =>
      minAttention == null && maxAttention == null && type == null && tag == null;

  /// Add the reach options (band shortcuts, bounds, type, tag) to [parser].
  static void addOptions(ArgParser parser) {
    parser
      ..addOption('min-attention', help: 'Pages at or above attention A (inclusive).')
      ..addOption('max-attention', help: 'Pages at or below attention A (inclusive).')
      ..addFlag('hot', negatable: false, help: 'Band 1.0 — the trust-read.')
      ..addFlag('warm', negatable: false, help: 'Band 0.7–0.9 — the attention field.')
      ..addFlag('cool', negatable: false, help: 'Band 0.4–0.6 — out of the foreground.')
      ..addFlag('cold', negatable: false, help: 'Band 0.1–0.3 — settled detail.')
      ..addOption('type',
          help: 'One mode: semantic | procedural | episodic '
              '| prospective | autobiographical.')
      ..addOption('tag', help: 'Only pages carrying TAG.');
  }

  /// Resolve the reach from parsed [args]. A band shortcut sets both bounds;
  /// explicit `--min/--max-attention` set them directly.
  static Reach from(ArgResults args) {
    final band = _band(args);
    return Reach(
      minAttention: band != null
          ? Attention.ofTenths(band.minTenths)
          : _attention(args['min-attention'] as String?),
      maxAttention: band != null
          ? Attention.ofTenths(band.maxTenths)
          : _attention(args['max-attention'] as String?),
      type: _type(args['type'] as String?),
      tag: args['tag'] as String?,
    );
  }

  List<MemPage> apply(List<MemPage> pages) => const PageSelector().select(
        pages,
        minAttention: minAttention,
        maxAttention: maxAttention,
        type: type,
        tag: tag,
      );

  static Band? _band(ArgResults args) {
    for (final b in Band.values) {
      if (args[b.name] == true) return b;
    }
    return null;
  }

  static Attention? _attention(String? s) => s == null ? null : Attention.parse(s);

  static MemType? _type(String? s) => s == null ? null : MemType.parse(s);
}
