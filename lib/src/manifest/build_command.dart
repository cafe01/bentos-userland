import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:file/local.dart';

import 'compose_engine.dart';
import 'path_resolver.dart';
import 'tree_roots.dart';

/// `manifest build <fqdn|->` — JIT-compose a being and print it to stdout.
///
/// A THIN COMMAND. The composition logic lives in [ComposeEngine] (the heart) over
/// [PathResolver] (href resolution). This command only: reads the entrypoint,
/// drives the engine, serializes the result to stdout, maps a [ComposeException]
/// to stderr + exit 1.
///
/// ENTRYPOINT. An FQDN argument → resolved to (content, dir) via [PathResolver];
/// or `-`/stdin → content read raw, baseDir = cwd. Either way the engine receives
/// (source, baseDir). The composition level is read from WHAT it points at, never
/// a flag: a soul/organism file yields the whole being, a skill yields that skill.
///
/// OUTPUT. Always stdout — a pure filter, in → out, no side effects, no deploy.
/// Persistence is a shell redirect; there is no install verb.
///
/// SCOPE NOTE (v1). Composition is the PURE-PREPROCESSOR pass only — recursive
/// `<xi:include>` resolution (see [ComposeEngine]). The `<binds to=…>` linker is
/// v2 and lives in a separate pass; this command does not know it exists.
final class BuildCommand extends Command<int> {
  @override
  String get name => 'build';

  @override
  String get description =>
      'Compose an atom, molecule, or organism and print to stdout.';

  @override
  Future<int> run() async {
    final roots = resolveTreeRoots();
    final resolver = PathResolver(const LocalFileSystem(), roots);
    final engine = ComposeEngine(resolver);

    final String source;
    final String baseDir;

    final arg = argResults!.rest.firstOrNull;
    if (arg == null || arg == '-') {
      source = await stdin.transform(const SystemEncoding().decoder).join();
      baseDir = Directory.current.path;
    } else {
      final resolved = resolver.resolve(arg, Directory.current.path);
      if (resolved == null) {
        stderr.writeln('manifest build: cannot resolve: $arg');
        return 1;
      }
      source = resolved.content;
      final cp = resolved.canonicalPath;
      baseDir = cp.substring(0, cp.lastIndexOf('/'));
    }

    try {
      final doc = engine.compose(source, baseDir);
      stdout.writeln(doc.toXmlString(pretty: true));
      return 0;
    } on ComposeException catch (e) {
      stderr.writeln(e.message);
      return 1;
    }
  }
}
