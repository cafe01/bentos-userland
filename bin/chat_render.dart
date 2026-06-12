/// chat-render — pure filter: ChatEvent JSONL on stdin → styled text on stdout.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:chat_render/chat_render.dart';

const _usage = '''
Usage: llm … | chat-render [options]
       chat-render [options] < fixture.jsonl

A pure filter: reads a ChatEvent JSONL stream on stdin and renders it to
human-readable styled text on stdout. SignatureDelta is always silently
dropped (opaque by contract). Everything else is dispatched by event type.

Content:
  --[no-]thinking      show/hide thinking blocks
                       (default: on — thinking is rendered dim/italic)
  --[no-]calls         show/hide function-call cards
                       (default: on)

Format:
  --[no-]ansi          ANSI color and styling
                       (default: auto — on if stdout is a TTY, off if piped)
  --[no-]unicode       Unicode glyphs (┌ └ → ⚠ ─ ┊) vs ASCII fallbacks (, ' > ! - |)
                       (default: auto — on if locale is UTF-8)
  --width <n>          max columns for fixed chrome (call-cards); never prose
                       (default: terminal width if TTY, 0 if piped; 0 = no limit)
  --compact            condensed output: suppresses the turn-boundary marker
                       and reduces call-card chrome; does not affect --ansi

Turn boundary:
  --[no-]boundary      emit a turn-end marker at Complete
                       (default: auto — on if stdout is a TTY, off if piped)

Other:
  -h, --help           print this help''';

ArgParser _buildParser() {
  return ArgParser()
    ..addFlag('thinking', defaultsTo: true, help: 'Render thinking blocks.')
    ..addFlag('calls', defaultsTo: true, help: 'Render function-call cards.')
    ..addFlag('ansi', defaultsTo: null, help: 'ANSI color and styling (auto: TTY).')
    ..addFlag('unicode',
        defaultsTo: null, help: 'Unicode glyphs (auto: UTF-8 locale).')
    ..addFlag('compact',
        negatable: false, help: 'Condensed output (suppress quiet chrome).')
    ..addFlag('boundary',
        defaultsTo: null, help: 'Turn-boundary marker at Complete (auto: TTY).')
    ..addOption('width', help: 'Column budget for fixed chrome (0 = no limit).')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Print this help.');
}

Future<void> main(List<String> args) async {
  final parser = _buildParser();

  ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('chat-render: ${e.message}');
    stderr.writeln(_usage);
    exit(2);
  }

  if (results['help'] as bool) {
    stdout.writeln(_usage);
    exit(0);
  }

  if (results.rest.isNotEmpty) {
    stderr.writeln('chat-render: unexpected argument: ${results.rest.first}');
    stderr.writeln(_usage);
    exit(2);
  }

  int? width;
  if (results.wasParsed('width')) {
    final raw = results['width'] as String;
    width = int.tryParse(raw);
    if (width == null || width < 0) {
      stderr.writeln('chat-render: --width must be a non-negative integer');
      exit(2);
    }
  }

  final options = RenderOptions.fromArgs(
    thinking: results['thinking'] as bool,
    calls: results['calls'] as bool,
    ansiOverride: results.wasParsed('ansi') ? results['ansi'] as bool : null,
    unicodeOverride:
        results.wasParsed('unicode') ? results['unicode'] as bool : null,
    compact: results['compact'] as bool,
    boundaryOverride:
        results.wasParsed('boundary') ? results['boundary'] as bool : null,
    widthOverride: width,
  );

  exit(await ChatRenderer(options).run());
}
