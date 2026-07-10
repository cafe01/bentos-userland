import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:file/local.dart';
import 'package:xml/xml.dart';

import 'atom_editor.dart';
import 'atom_serializer.dart';
import 'edit_op.dart';
import 'path_resolver.dart';
import 'tree_roots.dart';

// Dense help shown by -h/--help. The audience is the agent mind, not a human
// skimming prose — every token pays rent.
const _editHelp = '''
Mutate one element or attribute of an atom — the write-half of the organ.

USAGE
  manifest edit <id> <verb> <selector> [handles]

SELECTOR  schema-blind — the document is the schema
  <tag>        an element under <atom>  (telos, capacity, principle, …)
  @<attr>      an attribute on <atom>   (@v)

VERBS
  add    <tag> [name]           create element; errors if it exists  (body on stdin)
  set    <tag> [name]           create-or-replace element body       (body on stdin)
  set    @<attr> <value>        set atom attribute                   (value on argv)
  remove <tag> [name]           delete element                       (no stdin)
  rename <tag> <name> <new>     rewrite an element's name= handle    (no stdin)

  [name] addresses one of several same-tag elements by its name= handle.
  Omit it only for a bare (handle-less) element; if named instances exist,
  a handle is required.

EXAMPLES
  manifest edit anamnesis.faculty set @v 0.3
  echo "…" | manifest edit anamnesis.faculty set telos
  echo "…" | manifest edit anamnesis.faculty add capacity recollection
  manifest edit anamnesis.faculty rename capacity recollection remembrance

OPTIONS
  --dry-run    Print a unified diff and write nothing.
  -h, --help   Print this usage information.''';

final class EditCommand extends Command<int> {
  @override
  String get name => 'edit';

  @override
  String get description =>
      'Mutate one element or attribute of an atom — the write-half of the organ.';

  // Override usage so -h/--help shows the dense help, not ArgParser's output.
  @override
  String get usage => _editHelp;

  @override
  final ArgParser argParser = ArgParser()
    ..addFlag('dry-run',
        negatable: false, help: 'Print a unified diff and write nothing.');

  @override
  Future<int> run() async {
    final dryRun = argResults!['dry-run'] as bool;
    // Pure positional grammar: <id> <verb> <selector> [handles…].
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      stderr.writeln('manifest edit: id required');
      stderr.writeln('Usage: manifest edit <id> <verb> <selector> [handles]');
      return 1;
    }
    final id = rest.first;
    final opArgs = rest.sublist(1);

    // Resolve id → file
    final localFs = const LocalFileSystem();
    final roots = resolveTreeRoots(Platform.environment);
    final resolver = PathResolver(localFs, roots);
    final resolved = resolver.resolve(id, Directory.current.path);
    if (resolved == null) {
      stderr.writeln('manifest edit: cannot resolve: $id');
      stderr.writeln('  Hint: run `manifest ls` to see available ids.');
      return 1;
    }

    // Whether a body is read from stdin is decided by the GRAMMAR, not by
    // whether stdin happens to be a pipe. Only `add`/`set` on an element carry a
    // body; attribute set (`@x`), remove, and rename must never touch stdin —
    // else, chained or run non-interactively, they block on an EOF that never
    // comes (the value already rode in on argv).
    final verbWord = opArgs.isNotEmpty ? opArgs.first : '';
    final selector = opArgs.length > 1 ? opArgs[1] : '';
    final needsBody = (verbWord == 'add' || verbWord == 'set') &&
        selector.isNotEmpty &&
        !selector.startsWith('@');

    String? stdinContent;
    if (needsBody) {
      if (stdin.hasTerminal) {
        stderr.writeln('manifest edit: $verbWord $selector: body required on stdin');
        return 1;
      }
      stdinContent = await stdin.transform(const SystemEncoding().decoder).join();
    }

    try {
      final op = const EditOpParser().parse(opArgs, stdinPresent: needsBody);
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
