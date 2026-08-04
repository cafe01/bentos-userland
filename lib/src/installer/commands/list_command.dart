import 'package:args/command_runner.dart';

import '../bentos_runner.dart';

/// `bentos list` — what this machine actually holds: every configured stream,
/// the version live, the names in it, and whether each is on the PATH.
///
/// Read from the links themselves rather than from any record of what was
/// installed, so the listing cannot drift from the disk.
final class ListCommand extends Command<void> {
  ListCommand(this.bentos);

  final BentosRunner bentos;

  @override
  String get name => 'list';

  @override
  String get description => 'List installed streams, versions and executables.';

  @override
  Future<void> run() async {
    final store = bentos.store;
    final out = bentos.out;
    out.writeln('prefix: ${bentos.config.prefix}   host: ${bentos.host}');
    for (final stream in bentos.config.streams.keys) {
      final version = store.currentVersion(stream);
      if (version == null) {
        out.writeln('$stream  (not installed)');
        continue;
      }
      final previous = store.previousVersion(stream);
      out.writeln('$stream  $version${previous == null ? '' : '   (previous: $previous)'}');
      for (final executable in store.namesIn(stream, version)) {
        final linked = store.ownsPathEntry(executable);
        out.writeln('  ${linked ? '·' : '!'} $executable${linked ? '' : '   (not linked — the PATH entry is not ours)'}');
      }
    }
  }
}
