/// The material gate: the library, over the real floor.
///
/// `contract_suite.dart` judges the channel against doubles, and a double is
/// blind to exactly one thing — the seam between this package and what it
/// stands on. Here the witness is a real `entity` on the PATH, the real
/// `bentos.chat` bodies installed from their own genesis, and a real Git tree.
/// Nothing here is minted by the code under judgment: the entity was authored
/// by hand in another repository, and this gate only installs it and speaks.
///
/// **It fails when the pieces are absent; it never skips.** A gate that rescues
/// itself is the polite form of the empty assert. That is also why it carries
/// its own tag and runs on its own target, away from the suite that runs fifty
/// times a day.
///
///     dart test -t material test/chat/material
///
@Tags(['material'])
library;

import 'dart:io';

import 'package:bentos_userland/bentos_chat.dart';
// Only the class: `Refused` means something else down there, and the two
// vocabularies must not be confused at the one point they meet.
import 'package:bentos_userland/entity.dart' show Entity;
import 'package:test/test.dart';

/// Where the entity's genesis is. An environment variable so the gate does not
/// presume a campus: any clone of `bentos.chat` answers.
String get chatSource =>
    Platform.environment['BENTOS_CHAT_SOURCE'] ?? '../../bentos.chat';

void main() {
  late Directory plot;

  setUpAll(() {
    _demand('entity', 'the primitive is not on PATH');
    _demand('place', 'the place organ is not on PATH');
    expect(
      Directory(chatSource).existsSync(),
      isTrue,
      reason: 'no bentos.chat genesis at $chatSource — clone it, or point '
          r'$BENTOS_CHAT_SOURCE at one. This gate does not skip.',
    );
  });

  setUp(() {
    plot = Directory.systemTemp.createTempSync('chat-material-');
    _run('place', ['init', '-n', 'material-gate'], at: plot.path);
    _run('entity', ['install', Directory(chatSource).absolute.path],
        at: plot.path);
  });

  tearDown(() => plot.deleteSync(recursive: true));

  /// The channel as any caller builds one: the two seams over the real floor.
  Channel open(String name, {String? cursor}) {
    final entity = Entity('bentos.chat', from: plot.path);
    final identity = GitIdentity.of(entity);
    return channelConstruction(
      name: name,
      acts: EntityActs(entity.instance(name), identity: identity),
      tree: EntityTree(entity.instance(name)),
      identity: identity,
      ticker: () => DispatchTicker(entity),
      cursor: cursor,
    );
  }

  /// Where the channel's ref stands, read through the primitive.
  String? tip(String name) =>
      EntityTree(Entity('bentos.chat', from: plot.path).instance(name)).tip();

  /// A voice to speak under. A participant IS the author of its commits, so
  /// giving this gate an identity is giving git one and nothing else — there is
  /// no registration to perform.
  void speakAs(String name, String email) {
    final repo = _run('entity', ['path', 'bentos.chat'], at: plot.path).trim();
    _run('git', ['-C', repo, 'config', 'user.name', name], at: plot.path);
    _run('git', ['-C', repo, 'config', 'user.email', email], at: plot.path);
  }

  test('the library opens a real channel, speaks into it, and reads it back',
      () async {
    speakAs('Alfred', 'alfred@bentos.life');
    final channel = open('fabrica');

    // Identity is the substrate's, read from the cascade the commit is signed
    // under — not from the directory this test happens to run in.
    expect(channel.me, const Handle('alfred', 'bentos.life'));

    // The channel does not exist until somebody joins: membership is the door.
    expect(channel.roster(), throwsA(isA<NoSuchChannel>()));

    expect(await channel.join(displayName: 'Alfred'), isA<Acted>());

    final roster = await channel.roster();
    expect(roster.participants.map((p) => p.handle.local), ['alfred']);
    expect(roster.byHandle('alfred')!.displayName, 'Alfred');
    expect(roster.byHandle('alfred')!.isAway, isFalse);

    expect(await channel.say('raising the install gate'), isA<Acted>());
    expect(await channel.say('green'), isA<Acted>());

    // The transcript is in the order it arrived, and each message carries what
    // its own file states — read at the commit that added it.
    final transcript = await channel.history();
    expect(transcript.map((m) => m.body),
        ['raising the install gate', 'green']);
    expect(transcript.last.author.local, 'alfred');
    expect(transcript.last.spoken.isUtc, isTrue);
    expect(transcript.last.id, isNotEmpty);

    expect((await channel.history(limit: 1)).single.body, 'green');

    // Reading spawns nothing and commits nothing; the cursor is the caller's.
    final events = await channel.sync();
    expect(events.whereType<Spoke>().map((e) => e.message.body),
        ['raising the install gate', 'green']);
    expect(events, contains(isA<RosterChanged>()));
    expect(await channel.sync(), isEmpty);

    // Nobody set one, and the file is simply not there.
    expect(await channel.topic(), isNull);
  });

  test('the one gate: a non-member is refused, in the floor\'s own words',
      () async {
    speakAs('Alfred', 'alfred@bentos.life');
    await open('fabrica').join();
    final before = tip('fabrica');
    expect(before, isNotNull);

    speakAs('Stranger', 'stranger@elsewhere');
    final result = await open('fabrica').say('let me in');
    expect(result, isA<Refused>());
    expect((result as Refused).reason, contains('is not in bentos.chat:fabrica'));

    // A refusal leaves no residue, and the claim is asked of **the ref** and
    // not of the transcript: an empty transcript is what a broken reader also
    // reports, so it cannot tell a refusal from a reader that sees nothing.
    expect(tip('fabrica'), before);
  });

  test('the topic, the presence and the departure, over the real floor',
      () async {
    speakAs('Alfred', 'alfred@bentos.life');
    final channel = open('fabrica');
    await channel.join(displayName: 'Alfred');
    await channel.say('raising the install gate');

    expect(await channel.setTopic('the install gate'), isA<Acted>());
    expect(await channel.topic(), 'the install gate');
    expect(await channel.setTopic('green'), isA<Acted>());
    expect(await channel.topic(), 'green');

    // Away having said nothing is a declaration: the field exists and is empty,
    // which is what distinguishes it from presence. A reader that asked the
    // bytes instead of the path cannot tell the two apart.
    expect(await channel.away(), isA<Acted>());
    expect((await channel.roster()).byHandle('alfred')!.isAway, isTrue);
    expect((await channel.roster()).byHandle('alfred')!.away, '');
    expect(await channel.away('at the dentist'), isA<Acted>());
    expect((await channel.roster()).byHandle('alfred')!.away, 'at the dentist');
    expect(await channel.back(), isA<Acted>());
    expect((await channel.roster()).byHandle('alfred')!.isAway, isFalse);

    // The roster answers *who is here*; the transcript answers *what was said*.
    expect(await channel.leave(), isA<Acted>());
    expect((await channel.roster()).participants, isEmpty);
    expect((await channel.history()).single.body, 'raising the install gate');
  });

  test(
      'the commit is signed under the identity the content declares, never '
      "whatever GIT_AUTHOR_*/GIT_COMMITTER_* the caller's own environment "
      'happens to carry', () async {
    speakAs('Alfred', 'alfred@bentos.life');
    final channel = open('fabrica');
    await channel.join(displayName: 'Alfred');
    await channel.say('who signed this?');

    final repo = _run('entity', ['path', 'bentos.chat'], at: plot.path).trim();
    expect(
      _run('git', ['-C', repo, 'log', '-1', '--format=%an <%ae>', 'fabrica'],
          at: plot.path).trim(),
      'Alfred <alfred@bentos.life>',
      reason: 'the commit must be signed under the identity `git config` '
          'declares — the same read the content is written from — never '
          'whatever the ambient environment happens to carry',
    );

    final check = await ProcessBodies(
      place: plot.path,
      coordinate: 'bentos.chat:fabrica',
    ).run('check', const [], attempts: 1);
    expect(check.exitCode, 0, reason: check.stderr);
  });

  test('a non-member moves nothing, not even itself', () async {
    speakAs('Alfred', 'alfred@bentos.life');
    await open('fabrica').join();

    speakAs('Stranger', 'stranger@elsewhere');
    final stranger = open('fabrica');
    final before = tip('fabrica');
    expect(await stranger.leave(), isA<Refused>());
    expect(await stranger.setTopic('mine now'), isA<Refused>());
    expect(await stranger.away('gone'), isA<Refused>());
    expect(await stranger.back(), isA<Refused>());
    // Asked of the ref: four refusals and the line did not move once.
    expect(tip('fabrica'), before);
  });
}

void _demand(String binary, String complaint) {
  final found = Process.runSync(
    Platform.isWindows ? 'where' : 'which',
    [binary],
  );
  expect(found.exitCode, 0, reason: '$complaint. This gate does not skip.');
}

String _run(String binary, List<String> arguments, {required String at}) {
  final r = Process.runSync(binary, arguments, workingDirectory: at);
  if (r.exitCode != 0) {
    fail('$binary ${arguments.join(' ')} → ${r.exitCode}\n${r.stderr}');
  }
  return r.stdout as String;
}
