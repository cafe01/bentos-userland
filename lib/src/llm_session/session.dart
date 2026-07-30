/// The transactions of a `.llm` session. Each is a commit on the session's
/// repository: the author is the actor, the message is the semantic line, the
/// diff is the payload. Reading the log top to bottom replays the session's
/// whole reality in its own vocabulary.
library;

import 'dart:io';

import 'package:chat_inference/chat_inference.dart';

import '../entity/arming.dart';
import '../entity/git_entity.dart';
import 'fold.dart';
import 'schema.dart';

/// The default arming of a session: the assistant's runner, woken by every
/// transaction. It is a command line because a subscriber is a body to raise,
/// and the shell expands `$BENTOS_*` at wake time.
const String defaultRunnerCommand =
    r'llm session run "$BENTOS_ENTITY" --ref "$BENTOS_REF"';

/// The session's main line. A fork is a second ref over the same history.
const String mainRef = 'refs/heads/main';

final class Session {
  Session(this.entity, {this.ref = mainRef});

  final GitEntity entity;
  final String ref;

  Future<SessionState> get state async => SessionState.fold(await entity.tree(ref));

  Future<Debt> get debt async => (await state).debt;

  Future<String?> get tip => entity.head(ref);

  Future<List<Transaction>> get log => entity.log(ref);

  /// The session begins: the repository created, the runner armed, the channel
  /// chosen, and the system prompt laid as the leading message — it rides the
  /// data path, the subsystem having no ioctl for it.
  ///
  /// The leading message is laid *always*, empty when none was given, and
  /// before anything else in the tree. The leader is a position and not a
  /// presence: a session whose first record is the system message can have it
  /// revised at any point in its life, while one that opened without the record
  /// would need a transaction for laying it — a second way to say one thing.
  /// Write order is what makes the position, ids being minted in sequence.
  ///
  /// Arming is installed with the session, and is the whole of its machinery.
  /// An empty [runnerCommand] arms nothing — a session on a site that only
  /// renders it, whose transactions travel to wherever the assistant runs.
  static Future<Session> open(
    Directory dir, {
    required Channel channel,
    required String author,
    String title = 'New session',
    String? systemPrompt,
    String runnerCommand = defaultRunnerCommand,
  }) async {
    final entity = await GitEntity.init(dir);
    if (runnerCommand.isNotEmpty) Arming(entity).subscribe(runnerCommand);
    final session = Session(entity);

    final leader = Ulid.next();
    final tree = <String, String>{
      messagePath(leader):
          TurnRecord(id: leader, message: ChatMessage.systemText(systemPrompt ?? '')).encode(),
      channelFile: channel.encode(),
      titleFile: '$title\n',
    };
    // The one transaction whose expected parent is *no* parent: opening twice
    // over the same ref is refused by the same compare-and-swap as any race.
    await entity.commit(
      ref: session.ref,
      expectedParent: null,
      author: author,
      message: 'open · channel ${channel.deviceId} · system laid',
      tree: tree,
    );
    return session;
  }

  /// The user spoke: the full turn, text and attachments.
  Future<Transaction> say(ChatMessage message, {required String author}) async {
    final tree = await entity.tree(ref);
    final id = Ulid.next();
    tree[messagePath(id)] = TurnRecord(id: id, message: message).encode();
    return _commit(author: author, message: 'say · user · $id', tree: tree);
  }

  /// The assistant took its turn: content blocks, thinking, calls, the stop
  /// reason, and the marker of the model and knobs it ran under.
  ///
  /// [expectedParent] is what the runner folded from — passing it is what makes
  /// two bodies raised for one occurrence resolve into one reply.
  Future<Transaction> reply(
    ChatMessage message, {
    required ChatMetadata meta,
    required TurnMarker marker,
    required String author,
    String? expectedParent,
  }) async {
    final tree = await entity.tree(ref);
    final id = Ulid.next();
    tree[messagePath(id)] =
        TurnRecord(id: id, message: message, meta: meta, marker: marker).encode();
    return _commit(
      author: author,
      message: 'reply · assistant · stop ${_stopWord(meta.stopReason)} · $id',
      tree: tree,
      expectedParent: expectedParent,
    );
  }

  /// The executor answered one call. Several `return`s accrete into one
  /// ontology message: the results of one assistant turn travel together, and
  /// each is still its own transaction with its own author.
  Future<Transaction> returnResult({
    required String callId,
    required List<ChatContent> content,
    required String author,
    bool isError = false,
  }) async {
    final tree = await entity.tree(ref);
    final current = SessionState.fold(tree);
    final result =
        FunctionResultContent(callId: callId, content: content, isError: isError);
    final tail = current.last;
    final String id;
    if (tail != null && tail.isExecutorTurn) {
      id = tail.id;
      tree[messagePath(id)] =
          tail.withContent([...tail.message.content, result]).encode();
    } else {
      id = Ulid.next();
      tree[messagePath(id)] = TurnRecord(
        id: id,
        message: ChatMessage(role: ChatRole.user, content: [result]),
      ).encode();
    }
    return _commit(
      author: author,
      message: 'return · $callId${isError ? ' · error' : ''} · $id',
      tree: tree,
    );
  }

  /// A channel knob moved. Applies to the next turn and rewrites no past one —
  /// each turn keeps the marker it ran under.
  Future<Transaction> configure(
    Channel channel, {
    required String author,
    String? note,
  }) async {
    final tree = await entity.tree(ref);
    tree[channelFile] = channel.encode();
    return _commit(
      author: author,
      message: 'configure · ${note ?? channel.deviceId}',
      tree: tree,
    );
  }

  /// The user rewrote a past turn. Two demands wear one word: amending the
  /// leading system message leaves the conversation standing, while rewriting a
  /// turn to run again from there discards what followed it — the same
  /// transaction, distinguished by [discardTail]. Its non-destructive form is
  /// [forkAt], which keeps the original continuation alive.
  Future<Transaction> revise(
    String messageId,
    ChatMessage message, {
    required String author,
    bool discardTail = false,
  }) async {
    final tree = await entity.tree(ref);
    final target = TurnRecord.decode(messageId, tree[messagePath(messageId)]!);
    tree[messagePath(messageId)] = TurnRecord(
      id: messageId,
      message: message,
      meta: target.meta,
      marker: target.marker,
    ).encode();
    if (discardTail) {
      for (final path in tree.keys.toList()) {
        if (path.startsWith('$messagesDir/') &&
            path.compareTo(messagePath(messageId)) > 0) {
          tree.remove(path);
        }
      }
    }
    return _commit(
      author: author,
      message: 'revise · $messageId${discardTail ? ' · tail discarded' : ''}',
      tree: tree,
    );
  }

  /// The session's title moved: entity state, and therefore an act.
  Future<Transaction> rename(String title, {required String author}) async {
    final tree = await entity.tree(ref);
    tree[titleFile] = '$title\n';
    return _commit(author: author, message: 'rename · $title', tree: tree);
  }

  /// The fork: no transaction on this session at all, but a branch of it — the
  /// entity's branches meaning alternative continuations. Parentage is the
  /// shared history, never an invented field.
  Future<Session> forkAt(String commitId, {required String name}) async {
    final forked = 'refs/heads/$name';
    await entity.branch(ref: forked, at: commitId);
    return Session(entity, ref: forked);
  }

  /// Every transaction past `open` is written onto a tip: [expectedParent] when
  /// the caller folded from one, the current tip otherwise.
  Future<Transaction> _commit({
    required String author,
    required String message,
    required Tree tree,
    String? expectedParent,
  }) async {
    return entity.commit(
      ref: ref,
      expectedParent: expectedParent ?? await entity.head(ref),
      author: author,
      message: message,
      tree: tree,
    );
  }
}

String _stopWord(ChatStopReason r) => switch (r) {
      EndTurn() => 'end_turn',
      MaxTokens() => 'max_tokens',
      StopSequence() => 'stop_sequence',
      FunctionCall() => 'tool_use',
      ContentFilter() => 'content_filter',
    };
