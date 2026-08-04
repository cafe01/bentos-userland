import 'package:args/command_runner.dart';

import '../bentos_runner.dart';
import '../store.dart';

/// `bentos list` — what this machine actually holds: every configured stream,
/// the version live, the names in it, and whether the file on the PATH is
/// really that version's artifact.
///
/// Content is read from the disk by hashing, never from a record of what was
/// installed — `state.json` says which version the disk is *supposed* to agree
/// with, and where the two disagree that is the finding, not a bug.
///
/// **Drift is reported twice**: as a line for a person and as
/// [BentosRunner.driftExit] for a program, so a script asking "is this machine
/// still the version it says it is?" never parses this text.
final class ListCommand extends Command<void> {
  ListCommand(this.bentos);

  final BentosRunner bentos;

  @override
  String get name => 'list';

  @override
  String get description =>
      'List installed streams, versions and executables (exit ${BentosRunner.driftExit} when any has drifted).';

  @override
  Future<void> run() async {
    final store = bentos.store;
    final out = bentos.out;
    var drifted = false;
    out.writeln('prefix: ${bentos.config.prefix}   host: ${bentos.host}');
    for (final stream in bentos.config.streams.keys) {
      final version = store.currentVersion(stream);
      if (version == null) {
        out.writeln('$stream  (not installed)');
        continue;
      }
      final previous = store.previousVersion(stream);
      out.writeln('$stream  $version${previous == null ? '' : '   (previous: $previous)'}');
      for (final entry in store.drift(stream)) {
        drifted = drifted || entry.isDrift;
        out.writeln('  ${_mark(entry.state)} ${entry.name}${_note(entry.state)}');
      }
    }
    if (drifted) bentos.exitCode = BentosRunner.driftExit;
  }

  static String _mark(DriftState state) => switch (state) {
        DriftState.installed => '·',
        DriftState.missing => '?',
        DriftState.drifted => '!',
      };

  static String _note(DriftState state) => switch (state) {
        DriftState.installed => '',
        DriftState.missing => '   (missing — nothing at this name on the PATH)',
        DriftState.drifted => '   (drifted — the file on the PATH is not this version)',
      };
}
