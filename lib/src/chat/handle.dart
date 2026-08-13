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

/// Who the caller says it is — **a value it stated**, never a fact derived
/// about the machine it is running on. One installation serves many beings, so
/// anything read from this box answers a question nobody asked it.
///
/// Both halves are present, always: a participant with no address cannot be
/// told from another, and a display name is what a transcript reads by.
abstract interface class Identity {
  /// The handle this caller speaks under — the local part and the origin,
  /// taken from the address it stated.
  Handle get handle;

  /// The name shown beside the handle. Never null: a caller that stated an
  /// address and no name was refused before an [Identity] existed.
  String get displayName;
}

/// Nobody stated who is speaking, or what they stated is not an identity.
///
/// **A usage failure and nothing else.** Not *barred* — no gate refused this —
/// and not *contested* — nothing raced it. The command was not sayable, which
/// is why it must not be retried, and why the ref never moved.
final class NoIdentity implements Exception {
  const NoIdentity(this.reason);

  /// What is missing, and what would supply it — the whole of the message.
  final String reason;

  @override
  String toString() => '$chatOntology: $reason';
}
