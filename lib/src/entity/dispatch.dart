import 'dart:io';

import '../git/git.dart';
import '../git/git_ambient.dart';
import '../git/model/commit.dart';
import 'action.dart';
import 'arming/arming.dart';
import 'deliverer.dart';
import 'entity.dart';
import 'event.dart';
import 'journal.dart';
import 'transaction.dart';

/// **Dispatch** — what the primitive does with a published occurrence: match it
/// against this installation's [ArmingTables], wake what matched, and write down
/// what happened.
///
/// One implementation, reached through `Entity.emit`, which is the whole content
/// of the trampoline decision: the hook stops being the message system and
/// becomes six lines that hand Git's own phase and stdin to this. Matching,
/// lifetimes, provenance, detaching, journaling and the woken body's context all
/// live here, once.
///
/// It is **not on the public surface**. A caller reaches it through
/// `Entity.emit` and never constructs one, exactly as nobody constructs an
/// [ArmingTables] or a [Journal]: all three are infrastructure of one
/// installation.
final class Dispatch {
  const Dispatch({
    required this.entity,
    required this.gitDir,
    required this.place,
  });

  final Entity entity;

  /// The installation's repository — the **common** directory, resolved by the
  /// primitive and never passed in by a caller.
  final String gitDir;

  /// The place answering for this installation, laid as `BENTOS_PLACE`.
  final String place;

  /// What a commit that declares no action is journaled and matched as.
  ///
  /// A commit with no `Bentos-Action:` trailer is the ordinary condition of an
  /// act this system did not author, and [Event.noun] is required — so the
  /// absence is written down rather than left as a hole, and `*` matches it.
  static const String sentinelNoun = '-';

  /// What a hook returns to Git when a held gate said no.
  ///
  /// **One, and never the body's own code.** Git reads a hook's status as a
  /// boolean; `emit`'s return is also the coreutil's exit status, where 3, 4 and
  /// 5 already mean barred, contested and diverged. Forwarding a gate's private
  /// vocabulary into a channel that did not issue it is the flattening this
  /// front exists to delete — and the body's true code is on its
  /// [DeliveryLine], where it means what it says.
  static const int refusedCode = 1;

  /// Journals every triple in [updates], matches each against the arming table
  /// for [phase], and dispatches. One process start per **transaction**: every
  /// triple in one call is handled inside one invocation.
  ///
  /// At [EventPhase.attempted] every match runs held, in table order, and the
  /// return value is the exit code Git decides the transaction by — non-zero
  /// aborts it whole, at the first refusal a held command reports. At the other
  /// two phases every match has been handed to a detached deliverer before this
  /// returns, so the code is always `0`.
  ///
  /// **A refusal stops the transaction mid-list.** Occurrences already journaled
  /// stand and the remaining updates are never journaled: when the transaction
  /// stopped is itself a fact, and unwriting the earlier occurrences would make
  /// the journal lie about what was attempted.
  Future<int> emit(
    EventPhase phase,
    Iterable<TransactionRefUpdate> updates,
  ) async {
    final journal = Journal(gitDir, entity);
    for (final update in updates) {
      final id = instanceOf(update);
      if (id == null) continue;

      // **The trailer read, and what it means when it fails.** The commit is
      // read through the ambient port, whose own law scrubs a transaction's Git
      // environment from every invocation it makes — so this read is a plain
      // read of the installation's store. Probed on local receive-pack: no
      // quarantine survives to the `reference-transaction` hook, the objects
      // being migrated before it fires.
      //
      // Unreadable is still possible, and the two phases owe opposite answers.
      // At `.attempted` the act has not landed and the gates armed on it cannot
      // be run against a commit nobody can read: refuse, which is the
      // refuse-on-silence law — a publisher that cannot do its work must not let
      // the act through. At `.landed` and `.refused` the ref has already moved
      // and there is nothing left to protect, so the occurrence is journaled
      // with the sentinel noun and the transaction carries on. A throw here
      // would be the worst of both: an unread act aborting a landing.
      final RawCommit? record = _read(update.commit);
      if (record == null && phase == EventPhase.attempted) {
        stderr.writeln(
          'entity: ${entity.name}: cannot read ${update.commit.short} — '
          'refusing, because no gate can judge an act nobody can read',
        );
        return refusedCode;
      }

      final noun =
          record == null ? sentinelNoun : Action.nameIn(record.message) ?? sentinelNoun;
      final event = Event(
        instance: entity.instance(id),
        noun: noun,
        phase: phase,
        commit: update.commit,
        parent: update.old,
      );

      // **Before the table is read, and unconditionally.** An occurrence happens
      // whether or not anything is armed on it, and a `listen` reader promised
      // it needed nothing armed must see an unarmed installation. It is also
      // what lets a woken body find its own occurrence already written.
      journal.appendOccurrence(OccurrenceLine(
        entity: entity.name,
        event: event,
        actor: record?.author,
        // When the occurrence was dispatched here, which is not when the act was
        // authored — a pushed act arrives with a date of its own, on the commit,
        // and the journal is a record of this installation's own moment.
        instant: DateTime.now(),
        sentence: record == null ? null : Action.sayIn(record.message),
      ));

      final occurrence = _environmentFor(event);
      for (final armed in _armed(phase)) {
        if (!globMatches(armed.instance, id)) continue;
        if (!armed.pattern.matchesAction(noun)) continue;

        // **Fired means spent, and the pruning happens first.** At `.attempted`
        // a refusal leaves this call immediately, so a line pruned after its
        // command would survive its own firing.
        if (armed.once) ArmingTables(gitDir).remove(armed.id);

        final delivery = Delivery(
          gitDir: gitDir,
          place: place,
          entity: entity.name,
          subscriber: armed.id,
          command: armed.command,
          ref: update.ref,
          instance: id,
          noun: noun,
          phase: phase,
          commit: update.commit,
          parent: update.old,
          environment: occurrence,
        );

        if (phase != EventPhase.attempted) {
          await detach(delivery);
          continue;
        }
        if (await _hold(journal, delivery)) return refusedCode;
      }
    }
    return 0;
  }

  /// Runs a held body in line and journals what it answered. True when it
  /// refused.
  ///
  /// **A refusal speaks to the caller, not only to the journal.** The gate's own
  /// sentence is the whole account of why an act was barred — the substrate
  /// names no culprit — and it reaches a person because Git carries a hook's
  /// stderr up through `update-ref`. Buffered rather than streamed: two gates
  /// interleaved into one stream leave neither readable.
  Future<bool> _hold(Journal journal, Delivery delivery) async {
    final line = await perform(delivery);
    journal.appendDelivery(line);
    if (line.exitCode == 0) return false;
    stderr.writeln(
      'entity: refused by ${delivery.subscriber}: ${delivery.command.join(' ')}',
    );
    if (line.output.isNotEmpty) stderr.write(line.output);
    return true;
  }

  /// The lines armed for [phase] — **one table, never all three**. A phase reads
  /// only its own, which is what makes an `.attempted` gate silent at a landing
  /// without every reader having to remember to filter.
  List<Registration> _armed(EventPhase phase) {
    final table = ArmingTables(gitDir).tableFor(phase);
    if (!table.existsSync()) return const [];
    return [
      for (final line in table.readAsLinesSync()) ?ArmingTables.decode(line, phase),
    ];
  }

  /// The occurrence in an environment, which is how a woken *process* receives
  /// it. The vocabulary is [OccurrenceEnvironment]'s and is stated on the event
  /// page; the address register is laid by `run` too, and only a woken body gets
  /// the five that describe an occurrence.
  Map<String, String> _environmentFor(Event event) => {
        OccurrenceEnvironment.place: place,
        OccurrenceEnvironment.entity: entity.name,
        OccurrenceEnvironment.instance: event.instance.id,
        OccurrenceEnvironment.coordinate: '${entity.name}:${event.instance.id}',
        OccurrenceEnvironment.event: '${event.noun}.${event.phase.suffix}',
        OccurrenceEnvironment.phase: event.phase.suffix,
        OccurrenceEnvironment.noun: event.noun,
        OccurrenceEnvironment.sha: event.commit.sha,
        OccurrenceEnvironment.old: event.parent.sha,
      };

  RawCommit? _read(Commit commit) {
    try {
      return ambientGit.showCommit(gitDir, commit);
    } on Object {
      return null;
    }
  }

  /// The instance a triple acts upon, or null when the triple is **no occurrence
  /// at all**.
  ///
  /// Five skips, and none of them is cosmetic. A birth and a deletion are not
  /// acts upon an object; `genesis` is the structure instances are born from
  /// rather than one of them; a ref that did not move published nothing. The
  /// fifth is the one a rewrite drops: a fetch or a push moves `refs/remotes/*`
  /// and `refs/tags/*` inside the same transaction, and without it every
  /// ordinary fetch mints an occurrence whose instance is `remotes/origin/main`
  /// — an object that does not exist, journaled forever and matched against by
  /// every subscriber armed on `*`.
  static String? instanceOf(TransactionRefUpdate update) {
    const heads = 'refs/heads/';
    if (!update.ref.startsWith(heads)) return null;
    if (update.ref == Entity.genesisRef) return null;
    if (update.old == update.commit) return null;
    if (update.old == Commit.zero || update.commit == Commit.zero) return null;
    return update.ref.substring(heads.length);
  }
}
