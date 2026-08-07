/// Exactly one file under `lib/src/chat_client/` may import `nocterm` — the
/// render adapter. Everything else, including the pure core, stays framework
/// free so it is assertable with no terminal.
///
/// Asserts on the **import list**, never on the word appearing anywhere in
/// the file: a doc comment can say "no dart:io" truthfully while a naive
/// grep for the word would call the file dirty on its own honest disclaimer.
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('only the render adapter imports nocterm', () {
    final root = Directory('lib/src/chat_client');
    final offenders = <String>[];

    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final imports = _imports(entity.readAsStringSync());
      if (imports.any((uri) => uri.startsWith('package:nocterm/'))) {
        offenders.add(entity.path);
      }
    }

    expect(
      offenders,
      equals(['lib/src/chat_client/render/screen_view.dart']),
      reason: 'nocterm must be named by the render adapter alone',
    );
  });
}

final _importPattern = RegExp(r'''^\s*import\s+['"]([^'"]+)['"]''', multiLine: true);

Iterable<String> _imports(String source) =>
    _importPattern.allMatches(source).map((m) => m.group(1)!);
