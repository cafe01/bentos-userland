/// The names of the thing itself, in the one file everything may stand on.
///
/// A leaf on purpose: the ontology's name is what an exception prefixes itself
/// with, what a coordinate is checked against, and what a path is built under —
/// so the layers that carry no channel of their own still need it, and a
/// constant reached for by importing the caller's surface would make the leaves
/// depend on the top.
///
/// **One string serves identity, repository and PATH entry.** The entity is
/// `bentos.chat`, its repository is `bentos.chat`, and the command a person
/// types is `bentos.chat` — so a report that named itself anything else would
/// be naming a program the caller never invoked, which is exactly what `chat:`
/// did before somebody read it out loud.
library;

/// The ontology this is a channel of — and the name of the command.
const String chatOntology = 'bentos.chat';

/// Where the content lives.
///
/// **Namespaced by the composition law**: the root belongs to the genesis, so
/// nothing here reads outside this prefix — even though nothing fuses a
/// conversation, the law is general.
const String chatNamespace = 'chat';

const String participantsPath = '$chatNamespace/participants';
const String messagesPath = '$chatNamespace/messages';
const String topicPath = '$chatNamespace/topic';
