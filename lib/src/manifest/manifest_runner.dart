import 'package:args/command_runner.dart';

import 'build_command.dart';
import 'check_command.dart';
import 'ls_command.dart';
import 'new_command.dart';

/// The `manifest` coreutil — genesis engine of the periodic table.
final class ManifestRunner extends CommandRunner<int> {
  ManifestRunner() : super('manifest', 'Conjure a being from its particles.') {
    addCommand(BuildCommand());
    addCommand(NewCommand());
    addCommand(LsCommand());
    addCommand(CheckCommand());
  }
}
