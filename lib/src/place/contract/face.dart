/// `face` — the `place` coreutil: verbs over the seven components, the
/// vantage captured once, diagnostics printed, exit codes decided.
library;

import '../../entity/contract/contract.dart';

/// One process, one vantage, one actor where writing.
final class PlaceRunner {
  PlaceRunner({required this.vantage, this.actor, required this.out, required this.err});
  final String vantage;
  final Actor? actor;
  final Sink<String> out;
  final Sink<String> err;

  /// 0 did-it (including nothing found); 1 a decided refusal; 2 an invalid
  /// call; 64 a writing verb with no actor.
  Future<int> run(List<String> argv) => throw UnimplementedError('PlaceRunner.run');
}
