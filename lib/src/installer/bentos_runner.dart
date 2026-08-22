import 'dart:async';
import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;

import 'commands/install_command.dart';
import 'commands/list_command.dart';
import 'commands/rollback_command.dart';
import 'commands/update_command.dart';
import 'config.dart';
import 'installer.dart';
import 'path_shadows.dart';
import 'platform.dart';
import 'source.dart';
import 'store.dart';

/// The `bentos` coreutil's command runner — the installer that is also the
/// updater, and the only client we write against the release registry.
///
/// Everything the machine-facing half needs is injected: config, host
/// platform, HTTP client, streams. A test drives the same runner against a
/// fixture directory under its own temp root and never touches the operator's
/// machine.
final class BentosRunner {
  BentosRunner({
    StringSink? out,
    StringSink? err,
    BentosConfig? config,
    HostPlatform? host,
    http.Client? client,
    Map<String, String>? environment,
  })  : out = out ?? io.stdout,
        err = err ?? io.stderr,
        config = config ?? BentosConfig.load(environment: environment),
        _host = host,
        _client = client,
        _environment = environment {
    _runner = CommandRunner<void>(
      'bentos',
      'The installer that is also the updater — puts the userland on a machine that has nothing.',
    )
      ..addCommand(InstallCommand(this))
      ..addCommand(ListCommand(this))
      ..addCommand(UpdateCommand(this))
      ..addCommand(RollbackCommand(this))
      ..addCommand(SelfUpdateCommand(this));
  }

  final StringSink out;
  final StringSink err;
  final BentosConfig config;
  final HostPlatform? _host;
  final http.Client? _client;
  final Map<String, String>? _environment;

  late final CommandRunner<void> _runner;
  int exitCode = 0;

  /// The stream a command acts on when none is named.
  static const defaultStream = 'bentos-userland';

  /// **The exit codes of `bentos`, and this is where they are declared.**
  ///
  /// ```
  /// 0   the command did what it says, and there is nothing to know
  /// 1   it could not — no such stream, bad hash, network down
  /// 2   a finding, not a failure: something about this machine needs saying
  /// 64  the command line itself was wrong
  /// ```
  ///
  /// 2 rather than 3 because 3 already means *refused* across our surfaces, and
  /// a report of a finding refuses nothing.
  ///
  /// **The code carries the worst condition the command can see, never the one
  /// easiest to detect.** Drift was graded here first, and for a while it was
  /// graded alone — so a machine whose every name was shadowed, or whose prefix
  /// no PATH entry even reaches, exited 0 while the strictly worse thing was
  /// true: with drift you run something altered, with a shadow you run none of
  /// what was installed. A caller asking "is there anything I should know?"
  /// must get its answer from the code and never from the text.
  static const findingExit = 2;

  /// This binary's own name in the release — what `self-update` installs.
  static const selfName = 'bentos';

  VersionStore get store => VersionStore(home: config.home, prefix: config.prefix);

  PathShadows get shadows =>
      PathShadows.of(config.prefix, _environment ?? io.Platform.environment);

  Installer get installer => Installer(
        config: config,
        store: store,
        host: _host,
        client: _client,
        environment: _environment,
      );

  HostPlatform get host => _host ?? HostPlatform.detect();

  Future<void> run(List<String> args) async {
    try {
      await _runner.run(args);
    } on UsageException catch (e) {
      err.writeln(e);
      exitCode = 64;
    } on SourceException catch (e) {
      err.writeln('bentos: $e');
      exitCode = 1;
    } on IntegrityException catch (e) {
      err.writeln('bentos: $e');
      exitCode = 1;
    } on io.SocketException catch (e) {
      err.writeln('bentos: ${_offline(e.message)}');
      exitCode = 1;
    } on io.HandshakeException catch (e) {
      err.writeln('bentos: ${_offline(e.message)}');
      exitCode = 1;
    } on http.ClientException catch (e) {
      err.writeln('bentos: ${_offline(e.message)}');
      exitCode = 1;
    } on TimeoutException {
      err.writeln('bentos: ${_offline("timed out")}');
      exitCode = 1;
    }
  }

  /// A network failure the source did not already dress: the last net between
  /// a broken machine and a stack trace on someone else's terminal. The line
  /// says what failed and what to do, and never how it was thrown.
  static String _offline(String detail) =>
      'could not reach the network — $detail. Check the connection and run the same command again.';

  /// The one place an install is reported, so every verb that installs reads
  /// the same on the terminal.
  ///
  /// [headline] is what the act calls itself; the block under it is the same
  /// three words in every verb, because they classify the same thing — what
  /// happened to the bytes at each name in the prefix.
  void report(InstallReport report, {String? headline}) {
    out.writeln(headline ?? '${report.stream} ${report.version}  →  ${config.prefix}');
    if (report.installed.isNotEmpty) {
      out.writeln('  installed : ${report.installed.join(" ")}');
    }
    if (report.restored.isNotEmpty) {
      // The same rewritten bytes have two disjoint causes, and the line used to
      // assert one of them always: a machine moving forward from a version it
      // held was told its binaries "had drifted", which is a claim about damage
      // where there was none. The cause is read from what was live, not guessed
      // from the fact that something was written.
      final because = report.replaced == null
          ? '(had drifted from ${report.version})'
          : '(replacing ${report.replaced})';
      out.writeln('  restored  : ${report.restored.join(" ")}  $because');
    }
    if (report.unchanged.isNotEmpty) {
      out.writeln('  unchanged : ${report.unchanged.join(" ")}');
    }
    if (report.unavailable.isNotEmpty) {
      err.writeln(
        '  no $host build: ${report.unavailable.join(" ")}',
      );
    }
    if (report.replacedSelf(selfName)) {
      // The most delicate thing this program does, and the only one that
      // happened in silence: `bentos` replaced the binary the caller is inside
      // of, so the next `bentos` they type is a different program. It is said
      // out loud whether the swap moved forward or back.
      out.writeln(
        '  note      : $selfName replaced itself — the next `$selfName` you run is ${report.version}',
      );
    }
  }
}
