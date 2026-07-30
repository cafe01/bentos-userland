/// `llm models` — deficiency-marker command that prints the device catalog.
///
/// The ontologically correct form is `ls /dev/llm/` (VFS readdir), but the
/// kernel cannot yet enumerate its device namespace. This command exists so
/// the gap is in living code, not a comment. When the kernel grows readdir
/// over `/dev/llm/`, this becomes a thin shell over `ls` — or disappears.
///
/// It knows nothing of its own: the catalog is the one enumeration, and a
/// window offering the same devices reads the very same thing.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:chat_inference/chat_inference.dart';

import '../../device_catalog.dart';

const _note =
    'Note: stopgap — the canonical form is `ls /dev/llm/`, '
    'pending kernel namespace enumeration.';

class ModelsCommand extends Command<int> {
  /// Injectable for tests; defaults to [stdout]. [stdout] implements
  /// [StringSink] so the production path needs no adapter.
  final StringSink out;

  /// Injectable for tests; the machine's own catalog by default.
  final DeviceCatalog catalog;

  ModelsCommand({StringSink? out, DeviceCatalog? catalog})
      : out = out ?? stdout,
        catalog = catalog ?? const DeviceCatalog();

  @override
  String get name => 'models';

  @override
  String get description =>
      'List the devices the bootstrap knows about.\n'
      'Stopgap: the canonical form is `ls /dev/llm/`, '
      'pending kernel namespace enumeration.';

  @override
  Future<int> run() async {
    for (final device in await catalog.list()) {
      final capabilities = device.capabilities;
      out.writeln(
        capabilities == null
            ? '${device.id}  — unavailable: ${device.unavailable}'
            : '${device.id}  ${_summary(capabilities)}',
      );
    }
    out.writeln();
    out.writeln(_note);
    return 0;
  }
}

/// The device's own word, in one line: the room it thinks in, and the two
/// capabilities anything above it gates on.
String _summary(ChatCapabilities capabilities) => [
      '${capabilities.maxContextTokens} ctx',
      'out ${capabilities.maxOutputTokens}',
      'reasoning ${capabilities.reasoningSupport.name}',
      if (capabilities.supportsFunctions) 'functions',
      if (capabilities.supportedMimeTypes.isNotEmpty)
        capabilities.supportedMimeTypes.join(' '),
    ].join(' · ');
