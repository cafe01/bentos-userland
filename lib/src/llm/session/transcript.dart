/// The transcript, and the lens — the one thing the face invents.
///
/// Below this line the messages speak the vendors' ontology faithfully: a
/// function result rides as a `user`-role message because that is what the wire
/// says. Printing that raw attributes to a person words they never said.
/// Translating from the ontology of the machine into the ontology of the person
/// is exactly what a view is, and it happens here — never inside a renderer,
/// whose correctness is fidelity to the layer beneath it.
library;

import 'package:chat_inference/chat_inference.dart';

import 'coordinate.dart';
import 'primitive.dart';

/// One message as it sits in the tree, with the path it came from: the extension
/// is what says whether the bytes are one message or an assistant's event
/// stream, and the name is what a `revise` names.
final class StoredMessage {
  const StoredMessage(this.path, this.message);

  final String path;
  final ChatMessage message;
}

/// Which reading of the one transcript is on screen.
enum Lens {
  /// You and the agent: a call collapses to one line, reasoning is hidden, and
  /// the constitution is not a turn.
  conversation,

  /// The machinery: calls with their arguments, results whole, reasoning shown.
  work,

  /// Act, actor, sha — the primitive's own log, unretold. It is also where the
  /// commits that `fork` and `revise` take as arguments come from.
  audit,
}

/// Who a person understands to have spoken. Never the wire's role.
enum Speaker { you, agent, executor, constitution }

/// The attribution rule, alone and answerable on its own: a message's speaker is
/// read off what it carries, never off the role it travels under.
abstract interface class Attribution {
  Speaker of(ChatMessage message);
}

/// One turn as the person reads it: who spoke, and the blocks they said. The
/// blocks are text and never a laid-out line — indentation, colour and width
/// belong to the register, and a core that returned a formatted string would be
/// deciding for the screen it does not have.
final class RenderedTurn {
  const RenderedTurn(this.speaker, this.blocks, {this.path});

  final Speaker speaker;
  final List<String> blocks;

  /// Where it lives in the tree, so a register can offer it to `revise`.
  final String? path;
}

/// Reading the transcript, and reading it *at a commit*.
abstract interface class TranscriptReader {
  /// The message paths in order. Names carry their own chronology, so nothing
  /// sorts by time.
  Future<List<String>> messageNames(
    Coordinate coord, {
    Sha? asOf,
    Vantage vantage = const Vantage.here(),
  });

  /// The messages themselves, decoded through the ontology and never through
  /// Git: a `.jsonl` is an assistant's event stream folded by the library that
  /// owns folding, a `.json` is one message already.
  Future<List<StoredMessage>> transcript(
    Coordinate coord, {
    Sha? asOf,
    Vantage vantage = const Vantage.here(),
  });
}

/// The lens applied. Pure: same transcript and same lens, same turns.
abstract interface class TranscriptView {
  List<RenderedTurn> render(List<StoredMessage> transcript, Lens lens);
}
