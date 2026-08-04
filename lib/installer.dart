/// The `bentos` coreutil — the installer that is also the updater.
///
/// Named `installer` rather than `bentos` because `lib/src/bentos.dart` is the
/// syscall surface over the kernel, and the two are unrelated things.
library;

export 'src/installer/bentos_runner.dart';
export 'src/installer/config.dart';
export 'src/installer/installer.dart';
export 'src/installer/manifest.dart';
export 'src/installer/platform.dart';
export 'src/installer/source.dart';
export 'src/installer/state.dart';
export 'src/installer/store.dart';
