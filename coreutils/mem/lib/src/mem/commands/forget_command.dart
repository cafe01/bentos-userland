import 'package:args/command_runner.dart';

final class ForgetCommand extends Command<void> {
  @override
  String get name => 'forget';

  @override
  String get description => 'Remove the page and delete its content file. For discharged obligations only.';

  @override
  Future<void> run() async {
    throw UnimplementedError('forget not yet implemented');
  }
}
