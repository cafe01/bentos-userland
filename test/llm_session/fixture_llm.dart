// The `llm` coreutil with one more vendor registered: `/dev/llm/fixture/*`.
//
// This is the body the session's arming wakes during the walk. It differs from
// `bin/llm.dart` in exactly one line — which drivers the boot table holds —
// which is the seam the boot layer exists for: the program above is inert, and
// never learns which vendor answered.

import 'dart:io';

import 'package:bentos_userland/boot.dart';
import 'package:bentos_userland/llm.dart';

import 'fixture_driver.dart';

void main(List<String> args) async {
  registerLlmDriver(
    fixtureVendor,
    (model, channel) => fixtureChatDriver(model: model).serveChannel(channel),
  );
  exit(await LlmRunner().run(args));
}
