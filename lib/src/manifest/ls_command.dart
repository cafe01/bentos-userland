import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:file/local.dart';

import 'tree_lister.dart';
import 'tree_roots.dart';

/// `manifest ls <pattern>` — list matching particles in the tree, one per line.
///
/// A THIN COMMAND over [TreeLister]. It parses the dot-notation wildcard
/// pattern argument, drives the lister across the tree roots, and prints the
/// sorted FQDNs to stdout — one per line, a plain stream the shell pipes
/// (`ls` emits, you `grep`). No `--grep`.
final class LsCommand extends Command<int> {
  @override
  String get name => 'ls';

  @override
  String get description =>
      'List matching particles in the tree, one per line. '
      "Pattern is a dot-notation wildcard: '*' matches any run of whole "
      "segments (e.g. '*.skill'), '{a,b}' brace-expands to a union (e.g. "
      "'*.{agent,soul}'). No argument or bare '*' lists everything.";

  @override
  Future<int> run() {
    final pattern = argResults!.rest.firstOrNull ?? '*';
    final roots = resolveTreeRoots(Platform.environment);
    final fqdns = TreeLister(const LocalFileSystem(), roots).list(pattern);
    for (final fqdn in fqdns) {
      stdout.writeln(fqdn);
    }
    return Future.value(0);
  }
}
