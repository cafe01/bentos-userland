/// Who a participant is — and the whole of it, because nothing registers.
///
/// A participant **is the author of its commits**. There is no signup, no
/// nickname table and no account: identity comes from the substrate, which
/// already carries it, and nothing about identity is written into the content
/// that was not already on the commit.
library;

import 'ontology.dart';

/// A participant's identity, as the substrate already carries it.
///
/// [local] is the name mentioned in prose — `@alfred` — and it is a convention
/// a reader can see, never a routing key: addressing is legible in the prose
/// and the medium routes nothing.
final class Handle {
  const Handle(this.local, this.origin);

  /// The address this handle came from, split at the `@`.
  factory Handle.ofEmail(String email) {
    final at = email.indexOf('@');
    if (at < 0) return Handle(email, '');
    return Handle(email.substring(0, at), email.substring(at + 1));
  }

  /// The name mentioned in prose: the local part of the address.
  final String local;

  /// Where it came from — the host half.
  final String origin;

  /// The address whole, which is what the commit carries.
  String get email => origin.isEmpty ? local : '$local@$origin';

  /// **The handle is stored whole**, and two participants whose addresses
  /// differ only in the host share one [local]. Which of the two parts a face
  /// shows is that face's problem until it is proved to be the medium's.
  @override
  bool operator ==(Object other) =>
      other is Handle && other.local == local && other.origin == origin;

  @override
  int get hashCode => Object.hash(local, origin);

  @override
  String toString() => '@$local';
}

/// Who the caller is, resolved from **the cascade the commit will be signed
/// under** — the entity's own repository, never the directory the caller
/// happens to be standing in.
///
/// A collaborator and not a computation, for one reason: today the primitive
/// invents an author when none is passed, and this library must not compensate
/// for that by passing one. Holding identity behind a seam means the day the
/// floor stops inventing an author, nothing in `lib/src/chat/` changes.
abstract interface class Identity {
  /// The handle this caller speaks under.
  ///
  /// Required: a participant with no identity cannot be told from another, and
  /// guessing one would put words in somebody's mouth.
  Handle get handle;

  /// The display name the substrate holds, or null when it holds none.
  String? get displayName;
}

/// Nobody has stated who is speaking. Not a refusal — nobody decided
/// anything — and not a stumble either: it is a condition of the machine, or
/// of the caller having a name and no address.
final class NoIdentity implements Exception {
  const NoIdentity(this.reason);

  /// What is missing, and what would supply it — the whole of the message.
  final String reason;

  @override
  String toString() => '$chatOntology: $reason';
}
