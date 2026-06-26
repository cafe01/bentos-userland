import 'package:args/command_runner.dart';

import '../mem_runner.dart';
import '../model/mem_frontmatter.dart';
import '../model/mem_node.dart';

final class RememberCommand extends Command<void> {
  RememberCommand(this._runner) {
    argParser
      ..addOption('type', abbr: 't', help: 'Memory mode. Required on create. semantic | procedural | episodic | prospective | autobiographical.')
      ..addOption('weight', abbr: 'W', help: 'Weight 0.0–1.0. Required on create.')
      ..addOption('telos', help: 'The page\'s contract — one short sentence: why it exists.')
      ..addOption('file', abbr: 'f', help: 'Read the body from PATH instead of stdin.')
      ..addOption('gist', help: 'Manual gist override.')
      ..addMultiOption('link', help: 'External destination. Repeatable; replaces the links list.')
      ..addMultiOption('tag', help: 'Associative tag. Repeatable; replaces the tags list.')
      ..addOption('scope', abbr: 's', help: 'Scope label (default: place directory name).');
  }

  final MemRunner _runner;

  @override
  String get name => 'remember';

  @override
  String get description => 'Create or replace a page, atomically. Body from stdin or --file.';

  @override
  Future<void> run() async {
    final ctx = _runner.buildContext(globalResults!);
    if (ctx == null) return;

    final args = argResults!;
    final rest = args.rest;
    if (rest.isEmpty) {
      _runner.err.writeln('mem remember: page name required.');
      _runner.exitCode = 64;
      return;
    }
    final pageName = rest.first;

    final typeStr = args['type'] as String?;
    final weightStr = args['weight'] as String?;
    if (typeStr == null) {
      _runner.err.writeln('mem remember: --type is required.');
      _runner.exitCode = 64;
      return;
    }
    if (weightStr == null) {
      _runner.err.writeln('mem remember: --weight is required.');
      _runner.exitCode = 64;
      return;
    }

    final type = MemPageType.values.where((t) => t.name == typeStr).firstOrNull;
    if (type == null) {
      _runner.err.writeln('mem remember: unknown type: $typeStr');
      _runner.exitCode = 64;
      return;
    }
    final weight = double.tryParse(weightStr);
    if (weight == null) {
      _runner.err.writeln('mem remember: invalid weight: $weightStr');
      _runner.exitCode = 64;
      return;
    }

    // Resolve or create node.
    var node = ctx.node;
    final fileStr = args['file'] as String?;

    // Find existing page (if any).
    MemPage? existing;
    MemPageType? existingType;
    if (node != null) {
      for (final t in MemPageType.values) {
        final found = node.pagesOf(t).where((p) => p.name == pageName).firstOrNull;
        if (found != null) {
          existing = found;
          existingType = t;
          break;
        }
      }
    }

    final telosOpt = args['telos'] as String?;
    final gistOpt = args['gist'] as String?;
    final links = args['link'] as List<String>;
    final tags = args['tag'] as List<String>;
    final hasMetaChanges = telosOpt != null || gistOpt != null || links.isNotEmpty || tags.isNotEmpty;
    final hasBodySource = fileStr != null;

    String? newContent;

    if (existing != null && node != null) {
      // Update path.
      final existingContent = node.readContent(existing);

      if (hasBodySource) {
        // New body from file.
        final rawBody = await ctx.bodySource.read(filePath: fileStr);
        newContent = _buildContent(rawBody, telosOpt, gistOpt, links, tags, existingContent);
      } else if (hasMetaChanges) {
        // Frontmatter-only update — preserve body.
        newContent = _buildContent(null, telosOpt, gistOpt, links, tags, existingContent);
      }
      // else: weight-only reweight — no content change.

      ctx.writer.update(node, existingType!, existing,
          content: newContent, weight: weight, type: type);
    } else {
      // Create path — node may not exist yet.
      if (node == null) {
        // Create mem.yml stub so MemWriter.create can resolve agentDir.
        final agentDir = ctx.resolver.agentDirAt(ctx.place);
        ctx.fileSystem.directory(agentDir).createSync(recursive: true);
        final nodePath = ctx.resolver.nodePathAt(ctx.place);
        ctx.fileSystem.file(nodePath).writeAsStringSync(
          'agent: ${ctx.resolver.agent}\nscope: place\nedges:\n'
          '  episodic: []\n  semantic: []\n  prospective: []\n  procedural: []\n  autobiographical: []\n',
        );
        node = ctx.resolver.resolve(ctx.place)!;
      }

      final String rawBody;
      if (hasBodySource) {
        rawBody = await ctx.bodySource.read(filePath: fileStr);
      } else {
        rawBody = await ctx.bodySource.read();
      }
      newContent = _buildContent(rawBody, telosOpt, gistOpt, links, tags, null);
      ctx.writer.create(node, type, pageName, newContent, weight);
    }
  }

  /// Build new file content from raw body + frontmatter fields.
  ///
  /// When [existingContent] is provided and [rawBody] is null, preserves the
  /// existing body while updating only frontmatter.
  String _buildContent(
    String? rawBody,
    String? telos,
    String? gist,
    List<String> links,
    List<String> tags,
    String? existingContent,
  ) {
    String body;
    FrontmatterFields existing = const FrontmatterFields();

    if (existingContent != null) {
      final (fm, existingBody) = FrontmatterFields.parse(existingContent);
      existing = fm;
      body = rawBody ?? existingBody;
    } else {
      body = rawBody ?? '';
    }

    final newFm = FrontmatterFields(
      telos: telos ?? existing.telos,
      gist: gist ?? existing.gist,
      links: links.isNotEmpty ? links : existing.links,
      tags: tags.isNotEmpty ? tags : existing.tags,
    );

    if (newFm.isEmpty) return body;

    final buf = StringBuffer()..writeln('---');
    if (newFm.telos != null) buf.writeln('telos: ${newFm.telos}');
    if (newFm.gist != null) buf.writeln('gist: ${newFm.gist}');
    if (newFm.links != null && newFm.links!.isNotEmpty) {
      buf.writeln('links:');
      for (final l in newFm.links!) {
        buf.writeln('  - $l');
      }
    }
    if (newFm.tags != null && newFm.tags!.isNotEmpty) {
      buf.writeln('tags:');
      for (final t in newFm.tags!) {
        buf.writeln('  - $t');
      }
    }
    buf.write('---\n$body');
    return buf.toString();
  }
}
