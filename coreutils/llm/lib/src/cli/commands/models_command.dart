/// `llm models` — deficiency-marker command that lists the devices the
/// bootstrap knows about.
///
/// The ontologically correct form is `ls /dev/llm/` (VFS readdir), but the
/// kernel cannot yet enumerate its device namespace. This command exists so
/// the gap is in living code, not a comment. When the kernel grows readdir
/// over `/dev/llm/`, this becomes a thin shell over `ls` — or disappears.
library;

import 'dart:io';

import 'package:args/command_runner.dart';

import '../../config.dart';

const _note =
    'Note: stopgap — the canonical form is `ls /dev/llm/`, '
    'pending kernel namespace enumeration.';

class ModelsCommand extends Command<int> {
  /// Injectable for tests; defaults to [stdout]. [stdout] implements
  /// [StringSink] so the production path needs no adapter.
  final StringSink out;

  ModelsCommand({StringSink? out}) : out = out ?? stdout;

  @override
  String get name => 'models';

  @override
  String get description =>
      'List the devices the bootstrap knows about.\n'
      'Stopgap: the canonical form is `ls /dev/llm/`, '
      'pending kernel namespace enumeration.';

  @override
  Future<int> run() async {
    for (final device in knownDevices) {
      out.writeln(device);
    }
    out.writeln();
    out.writeln(_note);
    return 0;
  }
}
