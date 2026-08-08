import 'package:args/command_runner.dart';

import '../body_source.dart';
import '../gist_deriver.dart';
import '../mem_runner.dart';
import '../model/attention.dart';
import '../model/mem_page.dart';
import '../write_echo.dart';

/// `mem remember <topic>` — persist a body, atomically. Body from stdin or
/// `--file`; type, attention, tags set here, dates kept by the organ. A
/// `remember` with no body is refused, never a silent metadata patch. On an
/// inherited topic it replaces the ancestor's page in place — no local shadow —
/// and the echo names the `@place`.
final class RememberCommand extends Command<void> {
  RememberCommand(this._runner) {
    argParser
      ..addOption('type', abbr: 't', help: 'Memory mode. Required on create.')
      ..addOption('attention', abbr: 'A', help: 'Attention 0.0–1.0, in 0.1 steps. Required on create.')
      ..addOption('file', abbr: 'f', help: 'Read the body from PATH instead of stdin.')
      ..addOption('gist', help: 'Manual gist override.')
      ..addMultiOption('tag', help: 'Associative tag. Repeatable; replaces the tags list.');
  }

  final MemRunner _runner;

  @override
  String get name => 'remember';

  @override
  String get description => 'Persist a page body — create or replace, atomically.';

  @override
  Future<void> run() async {
    final store = _runner.buildStore(globalResults!);
    if (store == null) return;

    final rest = argResults!.rest;
    if (rest.length != 1) {
      _runner.err.writeln('mem: remember takes exactly one <topic>.');
      _runner.exitCode = 1;
      return;
    }
    final topic = rest.single;

    final existing = {for (final p in store.cascade()) p.topic: p}[topic];
    final creating = store.homeOf(topic) == null;

    final type = _resolveType(existing);
    if (type == null) return;
    final attention = _resolveAttention(existing);
    if (attention == null) return;

    final String body;
    try {
      body = await BodySource(stdinReader: _runner.stdinReader)
          .read(filePath: argResults!['file'] as String?);
    } on Exception catch (e) {
      _runner.err.writeln('mem: $e');
      _runner.exitCode = 1;
      return;
    }

    final String gist;
    try {
      gist = await GistDeriver(_runner.gistLlm)
          .derive(body, manualGist: argResults!['gist'] as String?);
    } on GistDerivationFailed catch (e) {
      _runner.err.writeln('mem: $e');
      _runner.exitCode = 1;
      return;
    }

    final tags = argResults!['tag'] as List<String>;
    final page = store.write(
      topic,
      type: type,
      attention: attention,
      tags: tags.isNotEmpty ? tags : (existing?.fields.tags ?? const []),
      gist: gist,
      body: body,
    );

    _runner.announceBank(store.bank);
    _runner.out.writeln(WriteEcho(store.vantage).remembered(page, created: creating));
  }

  MemType? _resolveType(MemPage? existing) {
    final raw = argResults!['type'] as String?;
    if (raw == null) {
      if (existing != null) {
        if (existing.fields.assumptions.any((a) => a.field == 'type' || a.field == 'frontmatter')) {
          _fail('remember: ${existing.topic}\'s type was assumed, not read — '
              'pass --type explicitly, or the guess is canonized silently.');
          return null;
        }
        return existing.fields.type;
      }
      _fail('remember: --type is required on create.');
      return null;
    }
    try {
      return MemType.parse(raw);
    } on FormatException catch (e) {
      _fail('mem: $e');
      return null;
    }
  }

  Attention? _resolveAttention(MemPage? existing) {
    final raw = argResults!['attention'] as String?;
    if (raw == null) {
      if (existing != null) {
        if (existing.fields.assumptions.any((a) => a.field == 'attention' || a.field == 'frontmatter')) {
          _fail('remember: ${existing.topic}\'s attention was assumed, not read — '
              'pass --attention explicitly, or the guess is canonized silently.');
          return null;
        }
        return existing.fields.attention;
      }
      _fail('remember: --attention is required on create.');
      return null;
    }
    try {
      return Attention.parse(raw);
    } on FormatException catch (e) {
      _fail('mem: $e');
      return null;
    }
  }

  void _fail(String message) {
    _runner.err.writeln(message);
    _runner.exitCode = 1;
  }
}
