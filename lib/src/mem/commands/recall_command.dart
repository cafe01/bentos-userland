import 'package:args/command_runner.dart';

import '../mem_runner.dart';
import '../model/mem_node.dart';

final class RecallCommand extends Command<void> {
  RecallCommand(this._runner) {
    argParser
      ..addOption('min-weight', help: 'Pages at or above weight W (0.0–1.0).')
      ..addOption('max-weight', help: 'Pages at or below weight W.')
      ..addOption('type', help: 'One mode: semantic | procedural | episodic | prospective | autobiographical.')
      ..addOption('tag', help: 'Pages carrying TAG.');
  }

  final MemRunner _runner;

  @override
  String get name => 'recall';

  @override
  String get description => 'Bring page(s) into the frame, in full — pure retrieval.';

  @override
  Future<void> run() async {
    final ctx = _runner.buildContext(globalResults!);
    if (ctx == null) return;

    final node = ctx.node;
    if (node == null) {
      _runner.err.writeln('mem recall: no memory found at place.');
      _runner.exitCode = 1;
      return;
    }

    final args = argResults!;
    final names = args.rest;
    final List<MemPage> pages;

    if (names.isNotEmpty) {
      // Name-based: find each page by name (predicates also apply).
      pages = [];
      for (final name in names) {
        final found = node.allPages.where((p) => p.name == name).firstOrNull;
        if (found == null) {
          _runner.err.writeln('mem recall: page not found: $name');
          _runner.exitCode = 1;
          return;
        }
        pages.add(found);
      }
    } else {
      // Predicate-based selection.
      pages = ctx.pageSelector.select(
        node,
        minWeight: _parseDouble(args['min-weight'] as String?),
        maxWeight: _parseDouble(args['max-weight'] as String?),
        type: _parseType(args['type'] as String?),
        tag: args['tag'] as String?,
      );
    }

    // Load bodies.
    final bodies = <String, String>{};
    for (final page in pages) {
      final content = node.readContent(page);
      if (content != null) bodies[page.name] = content;
    }

    ctx.out.write(ctx.recallRender.render(pages, bodies: bodies));
  }

  static double? _parseDouble(String? s) => s == null ? null : double.tryParse(s);

  static MemPageType? _parseType(String? s) {
    if (s == null) return null;
    return MemPageType.values.where((t) => t.name == s).firstOrNull;
  }
}
