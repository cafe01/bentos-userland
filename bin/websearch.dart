import 'dart:io';

import 'package:args/args.dart';
import 'package:websearch/websearch.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'engine',
      abbr: 'e',
      help: 'Search engine to use.',
      defaultsTo: 'ddgr',
      allowed: ['ddgr', 'googler'],
    )
    ..addOption(
      'count',
      abbr: 'n',
      help: 'Number of results (1–25).',
      defaultsTo: '10',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.');

  final ArgResults parsed;
  try {
    parsed = parser.parse(args);
  } on ArgParserException catch (e) {
    stderr.writeln('websearch: ${e.message}');
    stderr.writeln(parser.usage);
    exit(1);
  }

  if (parsed['help'] as bool) {
    stdout.writeln('Usage: websearch [options] <query>');
    stdout.writeln(parser.usage);
    exit(0);
  }

  final rest = parsed.rest;
  if (rest.isEmpty) {
    stderr.writeln('websearch: query required.');
    stderr.writeln('Usage: websearch [options] <query>');
    exit(1);
  }

  final query = rest.join(' ');
  final engine = Engine.parse(parsed['engine'] as String);
  final countRaw = int.tryParse(parsed['count'] as String);
  if (countRaw == null || countRaw < 1 || countRaw > 25) {
    stderr.writeln('websearch: --count must be between 1 and 25.');
    exit(1);
  }

  try {
    final results = await search(query, engine: engine, count: countRaw);
    for (final r in results) {
      stdout.writeln(r.toJsonl());
    }
  } on WebsearchEngineNotFoundError catch (e) {
    stderr.writeln(e);
    exit(1);
  } on WebsearchQueryError catch (e) {
    stderr.writeln(e);
    exit(2);
  }
}
