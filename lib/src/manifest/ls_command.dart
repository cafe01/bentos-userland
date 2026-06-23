import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:file/local.dart';

import 'tree_lister.dart';
import 'tree_roots.dart';

/// `manifest ls <glob>` — list matching particles in the tree, one per line.
///
/// A THIN COMMAND over [TreeLister]. It parses the glob argument, drives the
/// lister across the tree roots, and prints the sorted FQDNs to stdout — one per
/// line, a plain stream the shell pipes (`ls` emits, you `grep`). No `--grep`.
final class LsCommand extends Command<int> {
  @override
  String get name => 'ls';

  @override
  String get description => 'List matching particles in the tree, one per line.';

  @override
  Future<int> run() {
    final glob = argResults!.rest.firstOrNull ?? '**';
    final localFs = const LocalFileSystem();
    final roots = resolveTreeRoots(localFs, localFs.currentDirectory.path, Platform.environment);
    final fqdns = TreeLister(const LocalFileSystem(), roots).list(glob);
    for (final fqdn in fqdns) {
      stdout.writeln(fqdn);
    }
    return Future.value(0);
  }
}
