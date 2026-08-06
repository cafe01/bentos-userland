/// The plug point: two lines, and the contract suite judges the delivery.
///
/// The construction is `lib/src/llm/session/construction.dart`. No claim in
/// `contract_suite.dart` was touched — not to plug it in, and not to make it
/// pass. `plug_point_guard_test.dart` is what holds that this file stays
/// untagged now that a construction exists.
library;

import 'package:bentos_userland/src/llm/session/construction.dart';

import 'contract_suite.dart';

void main() => runSessionContract(sessionConstruction);
