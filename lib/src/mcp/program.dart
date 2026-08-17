import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:dart_mcp/server.dart';
import 'package:path/path.dart' as p;

/// Raised for anything that must kill the process before the handshake, so a
/// misconfigured server dies loudly in the host's log instead of presenting a
/// broken tool.
class StartupFailure implements Exception {
  StartupFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// How long a stopped program is given to die between `SIGTERM` and `SIGKILL`.
const _grace = Duration(seconds: 5);

/// How long the output streams of a stopped program are given to close before
/// the call reports whatever it collected. A killed program can leave a child
/// of its own holding the pipe open; that must not hang the call.
const _drainGrace = Duration(milliseconds: 250);

/// The command-line program this server presents, resolved and described once
/// at startup, then spawned once per tool call.
class Program {
  Program({
    required this.name,
    required this.path,
    required this.helpText,
    this.leading = const [],
  });

  /// The tool name: the last word of the presented invocation, with characters
  /// the protocol forbids mapped to `-`, unless overridden at the invocation.
  final String name;

  /// The resolved executable.
  final String path;

  /// Arguments fixed at the invocation, which lead every call. This is what
  /// lets a **subcommand** be the tool — `bentos-agent claude-spawn` — rather
  /// than the program that happens to carry it. A caller's own arguments
  /// follow these and cannot displace them, so the presented surface is
  /// exactly the one the invocation named.
  final List<String> leading;

  /// What the program printed for its help, captured verbatim at startup.
  final String helpText;

  final Set<io.Process> _live = {};

  /// Resolves [program] the way the shell would, captures its help, and
  /// returns the prepared program. Throws [StartupFailure] for either failure.
  static Future<Program> prepare(
    String program, {
    List<String> leading = const [],
    String helpFlag = '--help',
    String? toolName,
  }) async {
    final path = resolveProgram(program);
    if (path == null) {
      throw StartupFailure('cannot resolve program: $program');
    }

    // The probe runs the invocation that is being presented, not the program
    // that carries it: a subcommand's help is the description, and a program's
    // own help would describe a surface no caller of this tool can reach.
    final probe = [...leading, helpFlag];
    final spoken = [program, ...probe].join(' ');
    final io.ProcessResult help;
    try {
      help = await io.Process.run(path, probe);
    } on io.ProcessException catch (e) {
      throw StartupFailure('cannot run $spoken: ${e.message}');
    }
    if (help.exitCode != 0) {
      throw StartupFailure(
        '$spoken exited with ${help.exitCode}; no description to present',
      );
    }
    final helpText = (help.stdout as String);
    if (helpText.trim().isEmpty) {
      throw StartupFailure('$spoken printed nothing; no description to present');
    }

    return Program(
      name: toolName ??
          toolNameFor(leading.isEmpty ? p.basename(path) : leading.last),
      path: path,
      helpText: helpText,
      leading: leading,
    );
  }

  /// The single tool this server declares.
  Tool get tool => Tool(
    name: name,
    description: helpText,
    inputSchema: Schema.object(
      properties: {
        'args': Schema.list(
          description:
              'Argument strings, exactly as they would be typed after the '
              '${leading.isEmpty ? 'program name' : "'${[
                  p.basename(path),
                  ...leading,
                ].join(' ')}' command"}. No shell: no quoting, no expansion, '
              'one string per argument.',
          items: Schema.string(),
        ),
        'stdin': Schema.string(
          description: 'Text delivered to the program on standard input.',
        ),
        'timeout': Schema.int(
          description:
              'Milliseconds the call may run. The program is stopped when it '
              'expires.',
        ),
      },
      // A bare call runs the program with no arguments.
      required: [],
    ),
  );

  /// Runs the program once and reports what happened. Never throws for
  /// anything the program did; throws only for what the runner itself could
  /// not do (unstartable program), which `ToolsSupport` converts.
  Future<CallToolResult> call(CallToolRequest request) async {
    final arguments = request.arguments ?? const <String, Object?>{};
    final args = <String>[
      for (final arg in (arguments['args'] as List?) ?? const []) arg as String,
    ];
    final input = arguments['stdin'] as String?;
    final timeout = (arguments['timeout'] as num?)?.toInt();

    // The environment and the working directory are inherited, not curated.
    final process = await io.Process.start(path, [...leading, ...args]);
    _live.add(process);

    final out = StringBuffer();
    final err = StringBuffer();
    final outDone = process.stdout.transform(utf8.decoder).forEach(out.write);
    final errDone = process.stderr.transform(utf8.decoder).forEach(err.write);

    try {
      if (input != null) process.stdin.write(input);
      await process.stdin.close();
    } on io.IOException {
      // The program closed its input before we finished writing. That is its
      // own account to give, on its own streams.
    }

    var timedOut = false;
    int exitCode;
    if (timeout == null) {
      exitCode = await process.exitCode;
    } else {
      try {
        exitCode = await process.exitCode.timeout(
          Duration(milliseconds: timeout),
        );
      } on TimeoutException {
        timedOut = true;
        exitCode = await _stop(process);
      }
    }
    _live.remove(process);

    final drained = Future.wait([outDone, errDone]);
    if (timedOut) {
      await drained.timeout(_drainGrace, onTimeout: () => const []);
    } else {
      await drained;
    }

    final status = StringBuffer();
    if (timedOut) {
      status.writeln(
        'timed out after ${timeout}ms; the program was stopped.',
      );
    }
    status.write('exit status: $exitCode');

    return CallToolResult(
      isError: timedOut || exitCode != 0 ? true : null,
      content: [
        TextContent(text: status.toString()),
        TextContent(text: _labelled('stdout', out.toString())),
        TextContent(text: _labelled('stderr', err.toString())),
      ],
    );
  }

  /// Stops every program still running for this server. Called when the host
  /// closes the channel: no spawned process outlives the server.
  Future<void> stopAll() async {
    final live = _live.toList();
    _live.clear();
    await Future.wait([for (final process in live) _stop(process)]);
  }

  static Future<int> _stop(io.Process process) async {
    process.kill(io.ProcessSignal.sigterm);
    try {
      return await process.exitCode.timeout(_grace);
    } on TimeoutException {
      process.kill(io.ProcessSignal.sigkill);
      return process.exitCode;
    }
  }

  /// An empty stream is stated as empty rather than omitted, so the caller
  /// never wonders whether output was dropped.
  static String _labelled(String label, String text) =>
      text.isEmpty ? '$label: (empty)' : '$label:\n$text';
}

/// Resolves [program] the way the shell would: a bare name through `PATH`,
/// anything with a separator as a path. Returns the absolute path, or `null`
/// when nothing executable answers to the name.
String? resolveProgram(String program, {Map<String, String>? environment}) {
  if (program.isEmpty) return null;

  if (p.split(program).length > 1 || program.contains('/')) {
    final path = p.absolute(program);
    return _isExecutable(path) ? path : null;
  }

  final env = environment ?? io.Platform.environment;
  final search = env['PATH'] ?? env['Path'] ?? '';
  if (search.isEmpty) return null;
  for (final dir in search.split(io.Platform.isWindows ? ';' : ':')) {
    if (dir.isEmpty) continue;
    final candidate = p.join(dir, program);
    if (_isExecutable(candidate)) return p.absolute(candidate);
  }
  return null;
}

/// A `PATH` entry that is not executable is skipped, the way the shell skips
/// it, rather than resolved and then failing at the first call.
bool _isExecutable(String path) {
  final stat = io.FileStat.statSync(path);
  if (stat.type != io.FileSystemEntityType.file) return false;
  // Windows decides by extension, not by mode.
  return io.Platform.isWindows || stat.mode & 0x49 != 0;
}

/// The protocol accepts `[A-Za-z0-9_-]` in a tool name. Everything else in the
/// program's basename is mapped to `-`, predictably.
String toolNameFor(String basename) =>
    basename.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-');
