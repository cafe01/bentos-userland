import 'dart:io';

import 'package:path/path.dart' as p;

import '../place/place.dart';

/// Resolves the ordered list of tree roots the resolver searches, which(1)-style.
///
/// Tree roots are a SEARCH PATH, the same model as `.claude`: explicit overrides
/// first, then implicit defaults discovered through the Place primitive. Nobody
/// sets a variable by hand to make `manifest <fqdn>` work — the implicit roots
/// are always there.
///
/// ORDER (which(1) precedence — first hit wins downstream):
///   1. EXPLICIT — `env['BENTOS_TREE_PATH']`, colon-separated, in order, dropping
///      empties. The override/addition channel. Included verbatim, existence NOT
///      checked (an explicit root is the caller's assertion; the resolver checks
///      per-file anyway).
///   2. SPATIAL (implicit, appended) — for every place enclosing the working
///      directory, nearest first ([Place.current], then its ancestors up to the
///      machine root), the conventional `<place>/.bentos/tree` when that
///      directory EXISTS. Nested places EACH contribute a root — the cascade —
///      and nearest-first order is what makes the resolver's which(1) loop mean
///      nearest-wins per FQDN. The user tier is not special-cased: home is just
///      the implicit place in the chain, so `$HOME/.bentos/tree` falls out.
///
/// Implicit roots are appended only when their directory EXISTS (a missing
/// default must never appear and shadow nothing).
///
/// SPATIALITY IS THE PLACE'S, NOT OURS. Manifest walks no directories: the
/// primitive owns the upward chain, and manifest only probes the conventional
/// tree home AT each place the primitive returns. Consequence (deliberate
/// tightening): a `.bentos/tree` at an UNMARKED directory is not discovered —
/// mark the project as a place (`.place/`), or point BENTOS_TREE_PATH at it.
/// `.bentos/tree` is payload at a place, never a spatial marker of its own.
///
/// IO is raw `dart:io`, the same substrate as [Place] — hermetic tests ride
/// `runInMemoryFs`/`IOOverrides`, never an injected filesystem.
List<String> resolveTreeRoots(Map<String, String> env) {
  final roots = <String>[];

  // 1. EXPLICIT — BENTOS_TREE_PATH, colon-split, empties dropped, verbatim.
  final envPath = env['BENTOS_TREE_PATH'];
  if (envPath != null && envPath.isNotEmpty) {
    roots.addAll(envPath.split(':').where((s) => s.isNotEmpty));
  }

  // 2. SPATIAL — self first (`.ancestors` excludes the referent), then the
  //    chain up to the machine root; collect each place's tree when it exists.
  final here = Place.current;
  for (final place in [here, ...here.ancestors]) {
    final candidate = p.join(place.root.path, '.bentos', 'tree');
    if (Directory(candidate).existsSync()) {
      roots.add(candidate);
    }
  }

  return roots;
}
