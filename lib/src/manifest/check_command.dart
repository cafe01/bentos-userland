import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:file/local.dart';

import 'compose_engine.dart';
import 'path_resolver.dart';
import 'tree_roots.dart';

/// `manifest check <fqdn>` — validate that a being composes. A build dry-run.
///
/// SAME CIRCUIT AS build, MINUS the output. It drives the very same
/// [ComposeEngine] over the same entrypoint; the only difference is it discards
/// the flattened document and reports a verdict instead of printing it: exit 0 +
/// a terse OK on success, exit 1 + the [ComposeException] message on a missing
/// include or a cycle. No new component — check is build without the `print`.
final class CheckCommand extends Command<int> {
  @override
  String get name => 'check';

  @override
  String get description => 'Validate that a being composes — a build dry-run.';

  @override
  Future<int> run() async {
    final roots = resolveTreeRoots(Platform.environment);
    final resolver = PathResolver(const LocalFileSystem(), roots);
    final engine = ComposeEngine(resolver);

    final String source;
    final String baseDir;
    final String label;

    final arg = argResults!.rest.firstOrNull;
    if (arg == null || arg == '-') {
      source = await stdin.transform(const SystemEncoding().decoder).join();
      baseDir = Directory.current.path;
      label = '-';
    } else {
      final resolved = resolver.resolve(arg, Directory.current.path);
      if (resolved == null) {
        stderr.writeln('manifest check: cannot resolve: $arg');
        return 1;
      }
      source = resolved.content;
      final cp = resolved.canonicalPath;
      baseDir = cp.substring(0, cp.lastIndexOf('/'));
      label = arg;
    }

    try {
      engine.compose(source, baseDir);
      stdout.writeln('OK $label');
      return 0;
    } on ComposeException catch (e) {
      stderr.writeln(e.message);
      return 1;
    }
  }
}
