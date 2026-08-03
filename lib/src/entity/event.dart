/// The phase an occurrence is observed at. An entity publishes exactly one kind
/// of occurrence — **its own acts, qualified by phase** — and the vocabulary is
/// therefore the product of the type's declared actions with these three.
/// Nothing else is ever published, and there is no verb for publishing: an
/// occurrence without a commit would be neither durable, attributable nor
/// federated, which is precisely the weak second channel the model forbids.
enum EventPhase {
  /// The act is formed and not yet true: the commit object exists, the ref has
  /// not moved. Listeners here run **synchronously, inside the transaction**,
  /// and hold the act — this is the only phase with the power to **refuse**,
  /// and refusal leaves no residue because nothing was ever true.
  ///
  /// It cannot rewrite. By the time this fires the payload is already hashed;
  /// a listener that wants different content refuses and lets the actor redo
  /// it, or lands a compensating act of its own.
  attempted,

  /// It is true and published. Listeners here are **detached, fire and
  /// forget** — the landing is never held hostage to what it wakes — and their
  /// power is to **act again**, in their own name.
  landed,

  /// It did not pass. The trace remains, the effect does not.
  ///
  /// A refusal **knows that it did not pass, not why**: the substrate aborts a
  /// transaction whole and names no culprit, so the cause must come from
  /// whoever refused.
  refused;

  /// The suffix as it is written in a pattern and read in a table.
  String get suffix => name;
}

/// A subscription's selector — an action name (globs allowed) and a phase, as
/// `prompt.landed`, `*.attempted`, `tool-*.refused`.
///
/// The action name is the ontology's unit, so the grammar groups by it: the
/// three phases of one act read as one sealed family — `PromptAttempted`,
/// `PromptLanded`, `PromptRefused`.
final class EventPattern {
  const EventPattern({required this.action, required this.phase});

  /// The action selector: a name, or a glob over names. `*` matches any run of
  /// characters within a single action name.
  final String action;

  final EventPhase phase;

  /// Parses `<action>.<phase>`. Throws [FormatException] on a malformed
  /// pattern or an unknown phase — a subscription that cannot be read is never
  /// silently armed on nothing.
  factory EventPattern.parse(String text) {
    final dot = text.lastIndexOf('.');
    if (dot <= 0 || dot == text.length - 1) {
      throw FormatException('expected <action>.<phase>', text);
    }
    final suffix = text.substring(dot + 1);
    final phase = EventPhase.values.where((p) => p.suffix == suffix);
    if (phase.isEmpty) throw FormatException('unknown phase: $suffix', text);
    return EventPattern(action: text.substring(0, dot), phase: phase.first);
  }

  /// Whether [actionName] is selected by this pattern's action glob.
  bool matchesAction(String actionName) {
    final expr = RegExp(
      '^${action.split('*').map(RegExp.escape).join('.*')}\$',
    );
    return expr.hasMatch(actionName);
  }

  @override
  String toString() => '$action.${phase.suffix}';
}

/// One armed listener, as it stands in an installation's table.
///
/// **Arming is per installation** — the tables sit beside the repository, in
/// the place's plot, outside any tree — which is what lets one site run a
/// workload while another only watches, with one line of difference between two
/// deployments. It is deployment, never entity content, and it is never
/// tracked.
final class Registration {
  const Registration({
    required this.id,
    required this.instance,
    required this.pattern,
    required this.command,
    this.once = false,
  });

  /// The handle `off` takes. Stable for the life of the line.
  final String id;

  /// The instance watched, or `*` for every instance of the entity.
  final String instance;

  final EventPattern pattern;

  /// The command line woken, as argv. **Never a closure**: the listener is
  /// resurrected by a shell shim in another process, so a Dart function could
  /// never be it.
  ///
  /// It is invoked with the occurrence appended — the entity's own directory,
  /// the ref, the old and the new object names — which is everything a
  /// listener needs and nothing about a worktree, since a site armed to react
  /// may hold no worktree at all.
  final List<String> command;

  /// Whether this line removes itself when it fires — **the only lifecycle the
  /// floor offers a subscriber**. Everything else about a listener's life is
  /// the actor's own: liveness, a pid, a signal, a body that outlives its wake.
  ///
  /// The removal happens at the moment of firing and before the command runs,
  /// so a line can never fire twice — including at `.attempted`, where a
  /// refusal ends the transaction and would otherwise leave the shim no path to
  /// the pruning.
  final bool once;
}
