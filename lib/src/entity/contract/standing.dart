/// `standing` — where this copy stands, answered from a record. Read, never
/// measured; nothing here touches the network (R2.9.4).
library;

import 'spine.dart';

/// The slice of `Instance` this component owns.
abstract interface class InstanceStanding {
  /// How this copy stands against one source, as of the last contact with it
  /// (R2.9.1). Offline, always.
  ///
  /// [from] answers the distance from a named point instead of from this
  /// copy's own position (R2.9.1b) — what a holder of a pin asks, and the
  /// primitive knows nothing of why it was asked.
  Standing standingAgainst(String source, {Point? from});

  /// This instance against every source, by source name.
  Map<String, Standing> get standing;

  /// How many landings lie between two points of this line, [from] exclusive
  /// to [to] inclusive. Null when neither contains the other.
  int? landingsBetween({required Point from, required Point to});
}
