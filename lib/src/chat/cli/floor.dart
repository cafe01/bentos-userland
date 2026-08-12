/// What the face stands on: a channel, the bodies behind a gate that is not a
/// channel method, and the place's own answer about which channels are here.
///
/// Behind an interface for the reason every seam in this library is: the claims
/// about *what a verb prints and what it exits with* are claims about the face,
/// and a gate that had to install an entity to ask one would be judging the
/// floor instead. The real floor is one implementation of it, and it is what
/// ships.
library;

import '../../entity/entity.dart';
import '../../chat_client/ticker.dart';
import '../channel.dart';
import '../construction.dart';
import '../dispatch_ticker.dart';
import '../entity_seams.dart';
import '../handle.dart';
import '../seams.dart';

abstract interface class ChatFloor {
  /// A channel at [name], anchored at [place], resuming at [cursor], speaking
  /// as [identity] — or as [resolveChatIdentity] resolves it when omitted.
  Channel channel(
    String name, {
    required String place,
    String? cursor,
    Identity? identity,
  });

  /// Who the calling process speaks as — **the same identity [channel] signs
  /// under**, asked without opening a channel.
  ///
  /// A face needs this before it has a channel: a drain mark is keyed by the
  /// participant it belongs to, and the cursor a channel resumes from must be
  /// read before that channel is constructed. Resolving it a second time in the
  /// face would let the mark name someone other than the signer the moment the
  /// two resolutions disagree, so the floor answers once and both uses read the
  /// same answer. Throws [NoIdentity] exactly where [channel] would.
  Identity get identity;

  /// The entity's own functions at that coordinate — for `check`, which carries
  /// no seat, answers nobody, and is therefore not a member of [Channel].
  ChatBodies bodies(String name, {required String place, Identity? identity});

  /// The channels the installation at [place] carries, sorted. **The ambient
  /// walk's third step**, and it derives from disk rather than reading a store.
  List<String> channels(String place);

  /// A live view of the installation at [place]: fires whenever this
  /// installation dispatches, in place of a blind cadence. Installation-wide,
  /// exactly as dispatch itself is — one ticker serves every channel it
  /// carries.
  Ticker dispatchTicker(String place);
}

/// The floor as it really is: the entity primitive underneath, git's own
/// cascade for identity.
final class EntityFloor implements ChatFloor {
  EntityFloor({this.construct = channelConstruction});

  /// How a channel is built. Named so a face can be driven over a different
  /// construction without this class knowing there is more than one.
  final ChannelConstruction construct;

  /// Resolved once per process. Not caching it would mean a `git config`
  /// cascade per verb for a human caller, and — worse — two chances for the
  /// signer and the drain mark's owner to disagree.
  Identity? _identity;

  @override
  Identity get identity => _identity ??= resolveChatIdentity();

  Entity _entity(String place) => Entity(chatOntology, from: place);

  @override
  Channel channel(
    String name, {
    required String place,
    String? cursor,
    Identity? identity,
  }) {
    final entity = _entity(place);
    final resolved = identity ?? this.identity;
    return construct(
      name: name,
      acts: EntityActs(entity.instance(name), identity: resolved),
      tree: EntityTree(entity.instance(name)),
      identity: resolved,
      ticker: () => DispatchTicker(entity),
      cursor: cursor,
    );
  }

  @override
  ChatBodies bodies(String name, {required String place, Identity? identity}) =>
      ProcessBodies(
        place: place,
        coordinate: '$chatOntology:$name',
        identity: identity ?? this.identity,
      );

  @override
  List<String> channels(String place) =>
      [for (final instance in _entity(place).instances) instance.id]..sort();

  @override
  Ticker dispatchTicker(String place) => DispatchTicker(_entity(place));
}
