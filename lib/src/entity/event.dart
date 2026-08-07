import '../git/model/commit.dart';
import 'instance.dart';

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

/// One occurrence: an act qualified by phase, and exactly what the substrate
/// can read off a ref move — enough to match a subscription, never enough to
/// interpret.
///
/// It is what a `listen` reader receives and what a journaled occurrence is
/// built from. A woken *process* gets the same facts by environment instead,
/// since it is a body someone started and not a reader holding values.
final class Event {
  const Event({
    required this.instance,
    required this.noun,
    required this.phase,
    required this.commit,
    required this.parent,
  });

  final Instance instance;

  /// The payload the act deposited. **The name is the noun and never the
  /// verb** — `prompt`, not `say` — because the noun is all the substrate can
  /// read.
  final String noun;

  final EventPhase phase;

  /// The act's own commit. Never [Commit.zero] — an occurrence with no commit
  /// is not an occurrence, which is why a birth and a deletion are journaled as
  /// no occurrence at all rather than as one with a hole in it.
  final Commit commit;

  /// The value the ref held before this occurrence — **the parent**.
  ///
  /// A subscription answering [EventPhase.attempted] judges whether the act is
  /// legal *where it stands*, and where it stands is here: at that phase the
  /// ref has not moved, so folding at the tip would be leaning on the
  /// substrate's transaction timing to be right. An occurrence published
  /// without it is half an occurrence, and every gate in the system dies on its
  /// first line.
  final Commit parent;

  @override
  String toString() => '$noun.${phase.suffix}@${commit.short}';
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
  bool matchesAction(String actionName) => globMatches(action, actionName);

  @override
  String toString() => '$action.${phase.suffix}';
}

/// Whether [value] is selected by [glob], where `*` matches any run of
/// characters.
///
/// **One grammar, one home.** A registration selects on two axes — the instance
/// and the action — and they are the same glob read against different words; a
/// second implementation for the instance would be the same rule free to drift
/// from itself.
bool globMatches(String glob, String value) =>
    RegExp('^${glob.split('*').map(RegExp.escape).join('.*')}\$').hasMatch(value);

/// Who put a line in a table — **the line's provenance**, and the one property
/// of a registration that is about the registration rather than about what it
/// watches.
///
/// It is recorded because the two kinds have different owners: a hand-armed line
/// is a person's decision and nobody else's to touch, while a manifest-armed
/// line is a *reading* of what the entity declared and belongs to whoever
/// performs that reading again. Nothing re-arms today, which is exactly why the
/// mark is written now: the alternative is a format migration across every table
/// already on disk, at the moment the first consumer needs to tell them apart.
enum Provenance {
  /// Armed by a caller — `entity on`, `entity once`, or the API's own members.
  hand,

  /// Written by [Entity.install], reading the `on:` rows the entity's manifest
  /// declares.
  manifest;

  /// The word as it stands in a table.
  String get word => name;
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
    this.provenance = Provenance.hand,
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

  /// Whose reading put this line here. Default [Provenance.hand], because a
  /// line nobody marked was typed by somebody.
  final Provenance provenance;
}
