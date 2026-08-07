/// The register's own gate — the two pieces of it that hold judgement.
///
/// The subcommands are parse-one-call-one-print and have nothing in them to be
/// wrong about; the contract suite already judges the face they call. What is
/// judged here is the layout and the resolution, both pure: values in, lines or
/// a coordinate out, no process anywhere.
library;

import 'package:bentos_userland/src/llm/cli/session/printer.dart';
import 'package:bentos_userland/src/llm/cli/session/where.dart';
import 'package:bentos_userland/src/llm/session/coordinate.dart';
import 'package:bentos_userland/src/llm/session/face.dart';
import 'package:bentos_userland/src/llm/session/machine.dart';
import 'package:bentos_userland/src/llm/session/primitive.dart';
import 'package:bentos_userland/src/llm/session/transcript.dart';
import 'package:test/test.dart';

Fold _fold(SessionState state) => Fold(
      state: state,
      openCalls: const [],
      messages: 3,
      commit: const Sha('3f21ab'),
    );

void main() {
  group('the printer', () {
    test('a turn is its speaker and its first block, continuations aligned',
        () {
      final lines = renderTurns([
        const RenderedTurn(Speaker.agent, ['primeira', 'segunda']),
      ]);
      expect(lines, ['agent: primeira', '       segunda']);
    });

    test('the constitution is named by the word a person uses', () {
      final lines = renderTurns([
        const RenderedTurn(Speaker.constitution, ['you are terse']),
      ]);
      expect(lines.single, startsWith('system: '));
    });

    test('a turn with no blocks is no line at all', () {
      expect(renderTurns([const RenderedTurn(Speaker.you, [])]), isEmpty);
    });

    test("the state is printed in the floor's own words", () {
      expect(stateWord(SessionState.owesInference), 'owes_inference');
      expect(stateWord(SessionState.owesResults), 'owes_results');
      expect(stateWord(SessionState.idle), 'idle');
    });

    test('a screen carries the state it was pinned at, under the turns', () {
      final lines = renderScreen(Screen(
        pinnedAt: const Sha('3f21ab'),
        lens: Lens.conversation,
        turns: const [RenderedTurn(Speaker.you, ['olá'])],
        fold: _fold(SessionState.owesInference),
      ));
      expect(lines, ['you: olá', '-- owes_inference']);
    });

    test('the audit lens prints the acts and never the turns', () {
      final lines = renderScreen(Screen(
        pinnedAt: const Sha('3f21ab'),
        lens: Lens.audit,
        turns: const [RenderedTurn(Speaker.you, ['olá'])],
        fold: _fold(SessionState.idle),
        acts: [
          Act(
            sha: const Sha('3f21ab'),
            name: 'prompt',
            actor: 'cafe',
            instant: DateTime.utc(2026, 8, 7),
            sentence: 'user say',
          ),
        ],
      ));
      expect(lines.first, '3f21ab · prompt · cafe · user say');
      expect(lines, isNot(contains('you: olá')));
    });

    test('an act that said nothing prints no empty tail', () {
      final line = renderActs([
        Act(
          sha: const Sha('b71043'),
          name: 'reply',
          actor: 'assistant',
          instant: DateTime.utc(2026, 8, 7),
        ),
      ]).single;
      expect(line, 'b71043 · reply · assistant');
    });
  });

  group('which conversation', () {
    test('a bare name is an instance of the session ontology', () {
      final coord = parseCoordinate('demo');
      expect(coord.entity, 'bentos.llm');
      expect(coord.instance, 'demo');
    });

    test('a spelled coordinate names its own entity, which is never assumed',
        () {
      final coord = parseCoordinate('bentos.agent:alfred');
      expect(coord.entity, 'bentos.agent');
      expect(coord.instance, 'alfred');
    });

    test('a half-spelled coordinate is usage and not a guess', () {
      expect(() => parseCoordinate('bentos.llm:'),
          throwsA(isA<CoordinateMalformed>()));
      expect(() => parseCoordinate(':demo'),
          throwsA(isA<CoordinateMalformed>()));
      expect(() => parseCoordinate('a:b:c'),
          throwsA(isA<CoordinateMalformed>()));
    });

    test('the ambient variable answers when nothing was typed', () {
      final coord = coordinateFrom(
        null,
        environment: {sessionVariable: 'bentos.llm:demo'},
      );
      expect(coord.instance, 'demo');
    });

    test('nothing typed and nothing ambient is absent, never a default', () {
      // The environment is passed in rather than read: a variable set on the
      // machine running this would rescue the claim from the other side.
      expect(
        () => coordinateFrom(null, environment: const {}),
        throwsA(isA<CoordinateAbsent>()),
      );
    });

    test('the variable is derived from the ontology and never picked by hand',
        () {
      expect(sessionVariable, 'BENTOS_LLM');
    });
  });
}
