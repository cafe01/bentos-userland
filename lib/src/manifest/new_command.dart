import 'package:args/command_runner.dart';

/// `manifest new <family/path>` — scaffold a v0.1 particle (Intent Declaration).
final class NewCommand extends Command<int> {
  @override
  String get name => 'new';

  @override
  String get description => 'Scaffold a v0.1 particle (Intent Declaration).';

  @override
  Future<int> run() => throw UnimplementedError();
}
