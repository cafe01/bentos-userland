import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:bentos_userland/src/entity/deliverer.dart';

Future<void> main(List<String> args) async {
  // The deliverer's compiled entry point, before the runner and beneath it: it
  // is no verb of the coreutil — no options, no usage line — and it is produced
  // by nothing except dispatch detaching one.
  if (args.length == 2 && args.first == delivererVerb) return deliver(args.last);

  final runner = EntityRunner();
  await runner.run(args);
  exit(runner.exitCode);
}
