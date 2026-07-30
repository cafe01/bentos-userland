/// The reading verbs, and the rendering they share.
///
/// A session is legible on disk without any of our code — that is the schema's
/// promise, not this file's job. What these verbs add is the fold: the state a
/// pile of files stands in, the story the log tells, and the two seams a person
/// watches a live session through — the transaction as it lands, and the tokens
/// before it does.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chat_inference/chat_inference.dart';

import '../../../../entity.dart';
import '../../../../llm_session.dart';
import 'session_command.dart';

/// The heading every readout opens with: what this session is, and what it owes.
String renderHeading(SessionState state) =>
    '${state.title} · ${state.channel.deviceId} · ${state.debt}';

/// One record, addressed by its own id — the turn as a person reads it.
List<String> renderRecord(TurnRecord record) {
  final lines = <String>['${record.id}  ${_role(record.message.role)}'];
  for (final content in record.message.content) {
    lines.addAll(renderContent(content).map((line) => '    $line'));
  }
  final meta = record.meta;
  if (meta != null) {
    lines.add('    ${_vitals(meta)}');
  }
  return lines;
}

/// The content blocks, each marked by what kind of thing it is rather than by
/// its type's name: what is said, what was thought, what was called, what came
/// back.
List<String> renderContent(ChatContent content) {
  return switch (content) {
    TextContent(:final text) => text.trimRight().split('\n'),
    ThinkingContent(:final text) =>
      text.trimRight().split('\n').map((line) => '~ $line').toList(),
    RedactedThinkingContent() => ['~ (redacted)'],
    FunctionCallContent(:final id, :final name, :final arguments) => [
        '→ $name(${jsonEncode(arguments)})  $id',
      ],
    FunctionResultContent(:final callId, :final content, :final isError) => [
        '← $callId${isError ? ' (error)' : ''}',
        for (final nested in content)
          for (final line in renderContent(nested)) '  $line',
      ],
    BinaryContent(:final mimeType, :final uri) => [
        '[$mimeType] ${uri.length > 60 ? '${uri.substring(0, 57)}…' : uri}',
      ],
    CachePointContent() => const ['[cache point]'],
  };
}

/// One transaction, as a line: what happened, who did it, and what it touched.
/// The kind is the message's leading word — folded, never stored.
String renderTransaction(Transaction tx, TreeDiff diff) {
  final touched = [
    for (final path in diff.added) '+${_short(path)}',
    for (final path in diff.changed) '~${_short(path)}',
    for (final path in diff.removed) '-${_short(path)}',
  ].join(' ');
  return '${tx.id.substring(0, 7)}  ${tx.author.padRight(8)}  ${tx.message}'
      '${touched.isEmpty ? '' : '   $touched'}';
}

class SessionShowCommand extends SessionCommandBase {
  SessionShowCommand({super.out, super.err});

  @override
  String get name => 'show';

  @override
  String get description =>
      'The fold: what the session is, what it owes, and every turn in it.';

  @override
  String get invocation => 'llm session show <session.llm> [--ref <ref>]';

  @override
  Future<int> act() async {
    final state = await session.state;
    out.writeln(renderHeading(state));
    for (final record in state.records) {
      out.writeln();
      for (final line in renderRecord(record)) {
        out.writeln(line);
      }
    }
    return 0;
  }
}

class SessionLogCommand extends SessionCommandBase {
  SessionLogCommand({super.out, super.err});

  @override
  String get name => 'log';

  @override
  String get description =>
      "The session's whole reality, replayed in its own vocabulary — oldest first.";

  @override
  String get invocation => 'llm session log <session.llm> [--ref <ref>]';

  @override
  Future<int> act() async {
    final entity = session.entity;
    for (final tx in await session.log) {
      out.writeln(renderTransaction(tx, await entity.diff(tx.id)));
    }
    return 0;
  }
}

class SessionMonitorCommand extends SessionCommandBase {
  SessionMonitorCommand({super.out, super.err}) {
    argParser
      ..addOption(
        'tx',
        help: 'The transaction to render. Defaults to \$BENTOS_NEW — what the '
            'hook was woken by — and to the tip when nothing woke it.',
        valueHelp: 'commit',
      )
      ..addFlag(
        'arm',
        negatable: false,
        help: 'Arm this monitor on the session instead of rendering: one more '
            'line in the same table the runner is in, differing only in what '
            'the command does. Its output lands in the wake log.',
      )
      ..addFlag(
        'state',
        negatable: false,
        help: 'Also print the debt the transaction left.',
      );
  }

  @override
  String get name => 'monitor';

  @override
  String get description =>
      'Render the transaction that woke it — the reading actor, armed like any other.';

  @override
  String get invocation =>
      'llm session monitor <session.llm> [--tx <commit>]\n'
      '  or: llm session monitor <session.llm> --arm';

  @override
  Future<int> act() async {
    final entity = session.entity;
    if (argResults!['arm'] as bool) {
      Arming(entity).subscribe(monitorCommand);
      out.writeln('armed · ${Arming(entity).table.path}');
      return 0;
    }

    final id = argResults!['tx'] as String? ??
        Platform.environment['BENTOS_NEW'] ??
        await session.tip;
    if (id == null || id.isEmpty) {
      err.writeln('llm session monitor: nothing has happened yet');
      return 0;
    }
    final tx = (await session.log).where((t) => t.id == id).firstOrNull;
    if (tx == null) {
      err.writeln('llm session monitor: $id is not on ${session.ref}');
      return 66; // EX_NOINPUT
    }
    out.writeln(renderTransaction(tx, await entity.diff(tx.id)));
    if (argResults!['state'] as bool) {
      out.writeln('    ${SessionState.fold(await entity.tree(tx.id)).debt}');
    }
    return 0;
  }
}

/// The monitor as a table line. `$BENTOS_*` is expanded by the shell at wake
/// time, so one line serves every transaction — including one that arrived by a
/// push from another site.
const String monitorCommand =
    r'llm session monitor "$BENTOS_ENTITY" --ref "$BENTOS_REF" --tx "$BENTOS_NEW"';

class SessionWatchCommand extends SessionCommandBase {
  SessionWatchCommand({super.out, super.err}) : super(withRef: false) {
    argParser
      ..addOption(
        'turns',
        help: 'Leave after this many turns have completed. 0 stays until killed.',
        defaultsTo: '1',
        valueHelp: 'n',
      )
      ..addFlag(
        'thinking',
        negatable: false,
        help: 'Show the thinking as it streams, too.',
      );
  }

  @override
  String get name => 'watch';

  @override
  String get description =>
      'The live seam: the answer as it forms, which the log cannot serve. '
      'Persisted nowhere — the committed reply is the only truth.';

  @override
  String get invocation => 'llm session watch <session.llm> [--turns <n>]';

  @override
  Future<int> act() async {
    final entity = session.entity;
    final turns = int.tryParse(argResults!['turns'] as String) ?? 1;
    final thinking = argResults!['thinking'] as bool;

    // Binding is what makes the seam exist: before it, a runner publishes into
    // nothing. So a watch that starts after the turn has missed it — by design.
    final watch = await LiveWatch.bind(entity);
    final done = Completer<void>();
    var completed = 0;
    watch.events.listen((event) {
      switch (event) {
        case TextDelta(:final text):
          out.write(text);
        case ThinkingDelta(:final text):
          if (thinking) out.write(text);
        case FunctionCallStart(:final name, :final id):
          out.write('\n→ $name  $id');
        case FunctionArgsDelta(:final partialJson):
          out.write(partialJson);
        case Complete(:final metadata):
          out.writeln('\n${_vitals(metadata)}');
          completed++;
          if (turns > 0 && completed >= turns && !done.isCompleted) done.complete();
        default:
          break;
      }
    });
    await done.future;
    await watch.close();
    return 0;
  }
}

String _vitals(ChatMetadata meta) {
  final usage = meta.usage;
  final counts = usage == null
      ? ''
      : ' · ${usage.inputTokens} in / ${usage.outputTokens} out'
          '${usage.reasoningTokens == null ? '' : ' / ${usage.reasoningTokens} thought'}';
  return '${meta.model} · stop ${_stop(meta.stopReason)}$counts';
}

String _stop(ChatStopReason reason) => switch (reason) {
      EndTurn() => 'end_turn',
      MaxTokens() => 'max_tokens',
      StopSequence() => 'stop_sequence',
      FunctionCall() => 'tool_use',
      ContentFilter() => 'content_filter',
    };

String _role(ChatRole role) => switch (role) {
      ChatRole.system => 'system',
      ChatRole.user => 'user',
      ChatRole.assistant => 'assistant',
    };

String _short(String path) =>
    path.startsWith('$messagesDir/') ? path.substring(messagesDir.length + 1) : path;
