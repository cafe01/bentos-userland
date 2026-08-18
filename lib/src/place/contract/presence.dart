/// `presence` — the uniform address, making an instance present and releasing
/// it, per line, presence read from the copy and never cached (R15–R19).
library;

import 'dart:io';

import 'place.dart';

Never _todo(String member) => throw UnimplementedError('Presence.$member');

final class Presence {
  Presence(this.place);
  final Place place;

  /// R16 — `<lineRoot>/<thing>/<Instance.id>`. One rule, no exception,
  /// stated here and nowhere else. Answers whether or not anything stands.
  Directory addressOf(String thing, String instance) => _todo('addressOf');

  /// R13, R18 — read from `Copy.materializations`, filtered to this root.
  bool isPresent(String thing, String instance) => _todo('isPresent');
  Map<String, Set<String>> get presences => _todo('presences');

  /// R15, R19 — make present at the uniform address: a held instance at its
  /// pin, anything else at the tip. Idempotent where already present.
  Future<Made> present(String thing, String instance) => _todo('present');

  /// R19 — release the view; nothing is destroyed.
  Future<void> release(String thing, String instance) => _todo('release');
}

sealed class Made {
  const Made();
}
final class Present extends Made {
  const Present(this.at);
  final Directory at;
}
/// Entity R2.1.3 — the content is at no reachable source; nothing was made
/// and nothing will be retried on the person's behalf (Places R22).
final class Unfetchable extends Made {
  const Unfetchable(this.tried);
  final List<String> tried;
}
/// The thing is recorded and not stood here, or the instance is unknown.
final class NotStanding extends Made {
  const NotStanding(this.reason);
  final String reason;
}
