/// Gate 6 of the identity design: **no source under `lib/src/chat/` mentions
/// `user.name`, `user.email` or a git cascade.**
///
/// A grep is a weak witness for behaviour and a perfectly good one for
/// deletion. The other five gates prove what the faces *do*; this one proves
/// that the code which used to answer for a silent caller is gone rather than
/// merely unreferenced — the way to keep "nothing here reads the cascade" true
/// is that no code exists which could.
///
/// It costs nothing and needs no binaries, so it runs in the gate that runs
/// fifty times a day rather than on the material target.
library;

import 'dart:io';

import 'package:test/test.dart';

/// What must not appear. `GitIdentity` is the deleted class by name: the design
/// deleted it outright, and a file that names it again is the cascade coming
/// back under its own old sign.
const _forbidden = <String>[
  'user.name',
  'user.email',
  'GitIdentity',
];

void main() {
  test('no source under lib/src/chat reads a git cascade for who is speaking',
      () {
    final root = Directory('lib/src/chat');
    expect(
      root.existsSync(),
      isTrue,
      reason: 'run from the package root — this gate is a grep and cannot '
          'rescue itself into passing on an empty tree',
    );

    final sources = root
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    // The control: an empty corpus would pass every claim below.
    expect(sources, isNotEmpty, reason: 'no Dart sources found to judge');

    final offences = <String>[];
    for (final source in sources) {
      final lines = source.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final word in _forbidden) {
          if (lines[i].contains(word)) {
            offences.add('${source.path}:${i + 1}: $word — ${lines[i].trim()}');
          }
        }
      }
    }

    expect(
      offences,
      isEmpty,
      reason: 'identity enters as a value from the caller. Anything here that '
          'can read the machine is the 08/12 defect with a new address:\n'
          '${offences.join('\n')}',
    );
  });
}
