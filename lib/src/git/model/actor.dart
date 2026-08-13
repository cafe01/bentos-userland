/// The identity that took an action — written as the commit's author, and
/// therefore attributable, dated and federated for free.
///
/// An actor is a **who**: a person, a body of an agent, a daemon. The entity it
/// acts upon is a **thing** and never one of these, which is why this type
/// carries identity and nothing else — no capability, no address, no state. An
/// actor's own state, where it has any, lives in an entity of its own.
///
/// Authority does not live here either. A particular action is permitted,
/// forbidden, or conditional on a person saying yes; the answer is given at the
/// `.attempted` phase by whoever is armed there, reading this identity off the
/// action's payload. The floor never asks who may act.
///
/// **Both halves are stated, and the surface invents neither.** A name with no
/// address is refused rather than signed under something plausible: a derived
/// address is what a forgery is made of, and the machine's git cascade
/// describes whoever owns a source checkout and answers a question nobody asked
/// it. Faces refuse a silent caller before they reach this type; the
/// constructor is the backstop that makes an empty half unrepresentable on a
/// signing path.
final class Actor {
  /// An actor who states both halves. Throws [ArgumentError] on an empty one —
  /// the last position where a signing path could acquire a blank address.
  factory Actor(String name, {required String email}) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'an actor states a name');
    }
    if (email.trim().isEmpty) {
      throw ArgumentError.value(email, 'email', 'an actor states an address');
    }
    return Actor._(name, email);
  }

  const Actor._(this.name, this.email);

  /// The identity as it is written and read back — `alfred`, `cafe`,
  /// `llm-runner`. A seat is a role, so a name says what acted and never what
  /// it was permitted to do.
  final String name;

  /// The address written beside the name, stated by whoever acted.
  final String email;

  @override
  String toString() => '$name <$email>';
}

/// Who a record **says** acted — a claim of provenance, read back out of a
/// commit or a journal line. Nothing verifies it, and no surface may present it
/// as a signature.
///
/// **A separate type from [Actor], because a read is not a signing.** Records
/// written before the identity was mandatory, and journal lines that kept only
/// a name, carry less than an act may state; if that shortfall travelled in the
/// same type it would eventually reach a commit and sign it with a blank
/// address. Here it cannot: no member of the substrate accepts an
/// [Attribution], so an empty half can be reported and never written.
final class Attribution {
  const Attribution(this.name, this.email);

  /// The name the record carried.
  final String name;

  /// The address the record carried — empty where it held none, which is an
  /// honest account of a lossy record and never a value to sign under.
  final String email;

  @override
  String toString() => email.isEmpty ? name : '$name <$email>';
}
