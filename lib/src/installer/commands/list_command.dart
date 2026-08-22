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
/// **Every finding is reported twice**: as a line for a person and as
/// [BentosRunner.findingExit] for a program, so a script asking "is there
/// anything I should know about this machine?" never parses this text. Drift,
/// a shadowed name and an unreachable prefix are all findings and all raise the
/// code — the shadow above all, since a drifted name is one you run altered and
/// a shadowed one is a name you do not run at all.
///
/// And they are findings *about the machine*, so they go where the listing goes.
/// Sent to stderr, the shadow lines vanished under the most ordinary
/// redirection there is, leaving `bentos list > file` describing a machine in
/// perfect health that runs nothing this installer put on it. Only what is
/// about the run itself belongs on stderr.
final class ListCommand extends Command<void> {
  ListCommand(this.bentos);

  final BentosRunner bentos;

  @override
  String get name => 'list';

  @override
  String get description =>
      'List installed streams, versions and executables (exit ${BentosRunner.findingExit} on any finding: drift, a shadowed name, a prefix off the PATH).';

  @override
  Future<void> run() async {
    final store = bentos.store;
    final out = bentos.out;
    final shadows = bentos.shadows;
    var found = false;
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
        found = found || entry.isDrift;
        final shadow = shadows.ahead(
          entry.name,
          ourArtifact: store.artifactPath(stream, version, entry.name),
        );
        out.writeln('  ${_mark(entry.state)} ${entry.name}${_note(entry.state)}');
        if (shadow != null && !shadow.isOurs) {
          found = true;
          out.writeln(
            '    shadowed — ${shadow.path} answers "${entry.name}" before this '
            'prefix does, and it is not what I installed',
          );
        }
      }
    }
    if (shadows.prefixIsUnreachable) {
      found = true;
      out.writeln(
        'bentos: ${bentos.config.prefix} is not on your PATH — nothing installed '
        'here is what you run. Add it with:\n'
        '        export PATH="${bentos.config.prefix}:\$PATH"',
      );
    }
    if (found) bentos.exitCode = BentosRunner.findingExit;
  }

  static String _mark(DriftState state) => switch (state) {
        DriftState.installed => '·',
        DriftState.missing => '?',
        DriftState.drifted => '!',
      };

  static String _note(DriftState state) => switch (state) {
        DriftState.installed => '',
        DriftState.missing => '   (missing — nothing at this name in the prefix)',
        DriftState.drifted => '   (drifted — the file in the prefix is not this version)',
      };
}
