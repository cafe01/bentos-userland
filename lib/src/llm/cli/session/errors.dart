/// What a failure looks like from the outside: one sentence on stderr, and a
/// code a script can branch on.
///
/// Six codes, and each means one thing:
///
/// * `0`  — it happened.
/// * `1`  — the conversation has not been opened. An instruction, not an error.
/// * `3`  — refused, in the floor's own grade and the floor's own words. A
///          verdict: the same act will be refused again, and a script must
///          not loop on it.
/// * `4`  — contested, in the floor's own grade and the floor's own words.
///          Not a verdict: the ref moved under the act, nobody decided
///          anything, and a script that reads the tip again and says it
///          again terminates. Never folded into `3` — the two demand opposite
///          answers from the caller.
/// * `64` — usage (`EX_USAGE`), the value the sister coreutils already speak.
/// * `69` — `EX_UNAVAILABLE`: the verb exists and the floor does not offer it
///          yet. Distinct from every other code on purpose — the caller did
///          nothing wrong and retrying will not help until another front lands.
library;

import 'dart:io';

import 'package:args/command_runner.dart';

import '../../session/coordinate.dart';
import '../../session/face.dart';
import '../../session/primitive.dart';
import 'where.dart';

/// Exit code for a verb the floor still owes (`EX_UNAVAILABLE`).
const int owedCode = 69;

/// Run [body], turning every failure this layer knows about into a sentence and
/// a code. Nothing else in the register writes to stderr on a failure path, so
/// the mapping is stated exactly once.
Future<int> reporting(Future<int> Function() body) async {
  try {
    return await body();
  } on SessionNotOpen catch (e) {
    stderr.writeln(
      'llm session: ${_spell(e.coordinate)} has not been opened — '
      'open it with `llm session new`',
    );
    return 1;
  } on OwedByFloor catch (e) {
    stderr.writeln(e);
    return owedCode;
  } on CoordinateMalformed catch (e) {
    // Usage: the caller typed something that is not a coordinate, and that is
    // answered before anything is reached.
    stderr.writeln(
      "llm session: '${e.spelled}' is not a conversation — spell it "
      '<entity>:<instance> or <instance>',
    );
    return 64;
  } on CoordinateAmbiguous catch (e) {
    stderr.writeln('llm session: more than one conversation stands here:');
    for (final candidate in e.candidates) {
      stderr.writeln('  ${_spell(candidate)}');
    }
    return 64;
  } on CoordinateAbsent {
    stderr.writeln(
      'llm session: no conversation — pass --session or set $sessionVariable',
    );
    return 64;
  } on PrimitiveContested catch (e) {
    // Not a failure: the ref moved under the act. Reported at its own grade
    // so a script never mistakes it for a verdict.
    stderr.writeln('llm session: $e');
    return contestedCode;
  } on PrimitiveFailure catch (e) {
    // The floor's own words, and the floor's own grade where it gave one. A
    // refusal that arrived as 3 leaves as 3.
    stderr.writeln('llm session: $e');
    final code = e.exitCode;
    return code == null || code == 0 ? 1 : code;
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln(e.usage);
    return 64;
  }
}

String _spell(Coordinate coord) => '${coord.entity}:${coord.instance}';
