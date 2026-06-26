import 'package:args/command_runner.dart';

import '../mem_runner.dart';
import '../model/mem_node.dart';

final class ForgetCommand extends Command<void> {
  ForgetCommand(this._runner);

  final MemRunner _runner;

  @override
  String get name => 'forget';

  @override
  String get description => 'Remove the page and delete its content file. For discharged obligations only.';

  @override
  Future<void> run() async {
    final ctx = _runner.buildContext(globalResults!);
    if (ctx == null) return;

    final args = argResults!;
    final rest = args.rest;
    if (rest.isEmpty) {
      _runner.err.writeln('mem forget: page name required.');
      _runner.exitCode = 64;
      return;
    }
    final pageName = rest.first;

    final node = ctx.node;
    if (node == null) {
      _runner.err.writeln('mem forget: page not found: $pageName');
      _runner.exitCode = 1;
      return;
    }

    MemPage? target;
    MemPageType? targetType;
    for (final type in MemPageType.values) {
      final found = node.pagesOf(type).where((p) => p.name == pageName).firstOrNull;
      if (found != null) {
        target = found;
        targetType = type;
        break;
      }
    }

    if (target == null) {
      _runner.err.writeln('mem forget: page not found: $pageName');
      _runner.exitCode = 1;
      return;
    }

    ctx.writer.delete(node, targetType!, target);
  }
}
