/// `chat` — the program a person lives in: a terminal left open all day,
/// several rooms, one window.
library;

import 'dart:io';

import 'package:bentos_userland/bentos_chat.dart';
import 'package:bentos_userland/chat_client.dart';
import 'package:nocterm/nocterm.dart' show runApp;
import 'package:path/path.dart' as p;

const _usage = '''
Usage: chat [options] [room...]

Opens one window on one or more bentos.chat rooms, each a first-class
object with its own scrollback, unread mark and half-typed line. Rooms are
configured, never browsed: name them, or leave none and the place answers
when it carries exactly one.

  -C, --place <dir>   the vantage the rooms resolve from (default: cwd)
  -h, --help          print this help''';

Future<void> main(List<String> args) async {
  String? place;
  final rooms = <String>[];

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '-h' || arg == '--help') {
      stdout.writeln(_usage);
      exit(0);
    } else if (arg == '-C' || arg == '--place') {
      if (i + 1 >= args.length) {
        stderr.writeln('chat: $arg needs a value');
        exit(64);
      }
      place = args[++i];
    } else if (arg.startsWith('-')) {
      stderr.writeln('chat: unrecognized option: $arg');
      stderr.writeln(_usage);
      exit(64);
    } else {
      rooms.add(arg);
    }
  }

  const floor = EntityFloor();
  final cwd = Directory.current.path;
  final anchor = p.normalize(
    place == null ? cwd : (p.isAbsolute(place) ? place : p.join(cwd, place)),
  );

  var names = rooms;
  try {
    names = names.isEmpty
        ? [_ambient(floor, anchor)]
        : [for (final name in names) ChatCoordinate.parse(name)];
  } on MalformedCoordinate catch (e) {
    stderr.writeln('chat: $e');
    exit(64);
  } on NoAmbientChannel catch (e) {
    stderr.writeln('chat: $e');
    exit(64);
  }

  final channels = [
    for (final name in names) floor.channel(name, place: anchor),
  ];

  final program = ChatProgram(channels: channels, ticker: PeriodicTicker());
  await runApp(ChatApp(program: program));
}

/// The ambient room: the one room the place answers with, when it carries
/// exactly one. Anything else is the place declining to answer, and
/// guessing for the caller would be inventing an intention.
String _ambient(EntityFloor floor, String anchor) {
  final here = floor.channels(anchor);
  if (here.length == 1) return here.single;
  throw NoAmbientChannel(anchor, here);
}
