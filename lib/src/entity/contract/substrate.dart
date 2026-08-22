/// `substrate` — the git floor. The one file that names Git.
///
/// Two requirements are met or failed by the shape of a clone and by nothing
/// else, so the shape is a contract and not a choice: an engineer may choose
/// whether git is spawned or linked, and may not choose the filter, the
/// refspec, or the trailer.
library;

/// A copy is stood as a partial clone with blobs filtered: commits and trees
/// arrive, content does not.
const String cloneFilter = 'blob:none';

/// The fetch refspec every source is held under, into that source's
/// remote-tracking refs — the refs standing is measured against, live, by
/// `git rev-list --left-right --count` on every ask. Nothing of ours stores
/// what that measurement says.
String fetchRefspecFor(String source) =>
    '+refs/heads/*:refs/remotes/$source/*';

/// Where a source's positions are written down, as of the last contact.
String remoteTrackingRef(String source, String instance) =>
    'refs/remotes/$source/$instance';

/// One ref per instance: the instance's line on this copy.
String instanceRef(String instance) => 'refs/heads/$instance';

/// The commit trailer that carries an instance's displayed title, which is
/// what makes a far instance nameable on a copy holding no content.
const String titleTrailer = 'Title';

/// The commit trailer that names the source a landing arrived from. Absent on
/// a landing authored here.
const String arrivedFromTrailer = 'Arrived-From';

/// The three drivers a cadence rides — hooks in this copy, and a clock
/// registered with the host and never run by us.
enum Driver {
  /// A hook firing inside the process that just landed.
  onLanding,

  /// A hook firing inside the process the substrate spawns when a line is
  /// received.
  onArrival,

  /// A timer registered with the host's scheduler, at install and at refit.
  /// The one driver that can be unavailable, and is reported so.
  onClock,
}
