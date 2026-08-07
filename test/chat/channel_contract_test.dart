/// The plug point: two lines, and the contract suite judges the delivery.
///
/// The construction is `lib/src/chat/construction.dart`, and it is built: the
/// suite judges the delivery against the claims and never against a class, so
/// anything satisfying them is the medium's caller surface. Nothing in
/// `contract_suite.dart` may be touched to make a construction pass.
library;

import 'package:bentos_userland/bentos_chat.dart';

import 'contract_suite.dart';

void main() => runChannelContract(channelConstruction);
