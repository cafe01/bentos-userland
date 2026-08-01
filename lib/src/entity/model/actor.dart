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
final class Actor {
  /// An actor named by [name]. The mail address is derived where the substrate
  /// demands one, and carries no meaning of its own.
  const Actor(this.name, {this.email});

  /// The identity as it is written and read back — `alfred`, `cafe`,
  /// `llm-runner`. A seat is a role, so a name says what acted and never what
  /// it was permitted to do.
  final String name;

  /// The address written beside the name. Absent, the substrate is given a
  /// derived one; no consumer reads meaning out of it.
  final String? email;

  @override
  String toString() => email == null ? name : '$name <$email>';
}
