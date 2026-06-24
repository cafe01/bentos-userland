import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:file/local.dart';
import 'package:xml/xml.dart';

import 'atom_editor.dart';
import 'atom_serializer.dart';
import 'edit_op.dart';
import 'particle.dart';
import 'path_resolver.dart';
import 'tree_roots.dart';

// Dense help shown by -h/--help. The audience is the agent mind, not a human
// skimming prose — every token pays rent.
const _editHelp = '''
Mutate one particle of an atom — the write-half of the organ.

USAGE
  manifest edit <id> --<verb>-<particle> [name] [newName]  # body on stdin
  manifest edit <id> --set-<attr> <value>                  # scalar on argv

VERBS  add · set · remove · rename  (apply uniformly to every particle)
  add    — create particle         (named: handle argv + body stdin; singleton: stdin)
  set    — replace body/value      (particle: stdin; attribute: argv)
  remove — delete particle         (no stdin)
  rename — --rename-<p> <old> <new>  (named particles only; no stdin)

PARTICLES                               realm     arity
  Identity    essence · purpose         abstract  singleton
              trait                     abstract  named
  Capacity    capacity                  abstract  named
              protocol                  concrete  named
  Guidance    principle                 abstract  named
  Learning    knowledge · pattern       concrete  named
              antipattern               concrete  named

ATTRIBUTES  (--set-<attr> <value>, value on argv, no stdin)
  v

  requires · attracts — relation particles, deferred to v2.

OPTIONS
  --dry-run    Print a unified diff and write nothing.
  -h, --help   Print this usage information.''';

ArgParser _buildEditParser() {
  final p = ArgParser();

  p.addFlag('dry-run', negatable: false, help: 'Print a unified diff and write nothing.');

  // Prose particles — hidden: ArgParser validates the flag exists (rejects
  // true typos); the dense _editHelp replaces the generated usage output.
  for (final particle in editableParticles.keys) {
    final isNamed = editableParticles[particle]!.arity == Arity.named;
    p.addFlag('add-$particle', negatable: false, hide: true);
    p.addFlag('set-$particle', negatable: false, hide: true);
    p.addFlag('remove-$particle', negatable: false, hide: true);
    if (isNamed) p.addFlag('rename-$particle', negatable: false, hide: true);
  }

  // Attributes — hidden for same reason.
  for (final attr in editableAttrs) {
    p.addFlag('set-$attr', negatable: false, hide: true);
  }

  // v2 relation particles — hidden but declared so the parser gives a precise
  // "deferred to v2" error (via EditOpParser) instead of "unknown option".
  for (final rel in v2RelationParticles) {
    p.addFlag('add-$rel', negatable: false, hide: true);
    p.addFlag('set-$rel', negatable: false, hide: true);
    p.addFlag('remove-$rel', negatable: false, hide: true);
  }

  return p;
}

final class EditCommand extends Command<int> {
  @override
  String get name => 'edit';

  @override
  String get description =>
      'Mutate one particle of an atom — the write-half of the organ.';

  // Override usage so -h/--help shows the dense atlas, not ArgParser's
  // auto-generated cross-product of hidden flags.
  @override
  String get usage => _editHelp;

  @override
  final ArgParser argParser = _buildEditParser();

  @override
  Future<int> run() async {
    // Raw tokens — forwarded to EditOpParser which owns the semantic parsing.
    // argResults.arguments returns the original argument list as passed to parse().
    final rawArgs = argResults!.arguments;
    final dryRun = argResults!['dry-run'] as bool;
    final rest = rawArgs.where((a) => a != '--dry-run').toList();

    // First positional is the id; remaining tokens go to EditOpParser.
    final positionals = rest.where((a) => !a.startsWith('--')).toList();
    if (positionals.isEmpty) {
      stderr.writeln('manifest edit: id required');
      stderr.writeln('Usage: manifest edit <id> --<verb>-<particle> [name]');
      return 1;
    }
    final id = positionals.first;
    final opArgs = rest.where((a) => a != id).toList();

    // Resolve id → file
    final localFs = const LocalFileSystem();
    final roots =
        resolveTreeRoots(localFs, localFs.currentDirectory.path, Platform.environment);
    final resolver = PathResolver(localFs, roots);
    final resolved = resolver.resolve(id, Directory.current.path);
    if (resolved == null) {
      stderr.writeln('manifest edit: cannot resolve: $id');
      stderr.writeln('  Hint: run `manifest ls` to see available ids.');
      return 1;
    }

    // Read stdin if present (piped — not a terminal)
    final stdinPresent = !stdin.hasTerminal;
    String? stdinContent;
    if (stdinPresent) {
      stdinContent = await stdin.transform(const SystemEncoding().decoder).join();
    }

    try {
      final op = const EditOpParser().parse(opArgs, stdinPresent: stdinPresent);
      final opReady = stdinContent != null
          ? EditOp(
              verb: op.verb,
              targetKind: op.targetKind,
              target: op.target,
              name: op.name,
              newName: op.newName,
              content: stdinContent,
              value: op.value,
            )
          : op;

      final before = resolved.content;
      final doc = XmlDocument.parse(before);
      const AtomEditor().apply(doc, opReady);
      final after = serializeAtom(doc);

      if (dryRun) {
        await _printDiff(resolved.canonicalPath, before, after);
        return 0;
      }

      File(resolved.canonicalPath).writeAsStringSync(after);
      return 0;
    } on EditUsageException catch (e) {
      stderr.writeln('manifest edit: $e');
      return 1;
    } on EditConflictException catch (e) {
      stderr.writeln('manifest edit: $e');
      return 1;
    } on XmlException catch (e) {
      stderr.writeln('manifest edit: XML parse error: $e');
      return 1;
    }
  }

  Future<void> _printDiff(String path, String before, String after) async {
    if (before == after) {
      stdout.writeln('(no changes)');
      return;
    }
    final tmpDir = await Directory.systemTemp.createTemp('manifest_edit_');
    try {
      final a = File('${tmpDir.path}/before');
      final b = File('${tmpDir.path}/after');
      await a.writeAsString(before);
      await b.writeAsString(after);
      final result = await Process.run('diff', ['-u', a.path, b.path]);
      final out = result.stdout as String;
      stdout.write(out
          .replaceAll(a.path, '$path (before)')
          .replaceAll(b.path, '$path (after)'));
    } finally {
      await tmpDir.delete(recursive: true);
    }
  }
}
