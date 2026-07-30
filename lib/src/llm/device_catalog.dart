/// What devices there are, and what each one can do — the one enumeration of
/// `/dev/llm`, read by everything that needs to know: `llm models` at the
/// shell, a window offering a device picker, anything else that comes.
///
/// Capabilities are never written down here. They belong to the device and are
/// read from it — `open` then the `CHAT_GET_INFO` ioctl — so a table that
/// drifts from the driver is impossible by construction. What *is* written down
/// is the enumeration, because the kernel cannot yet list its own device
/// namespace ([knownDevices] says so and why).
///
/// A device that will not open is listed all the same, carrying the reason.
/// Silence would be a lie of a worse kind: an unregistered vendor and an absent
/// credential are facts about this machine, and a face that hides them leaves
/// the person wondering where their model went.
library;

import 'package:chat_inference/chat_inference.dart';

import '../../boot.dart';
import '../chat/bentos_chat_device.dart';
import 'config.dart';

/// How a device path becomes a device — the in-process portal by default.
typedef DeviceOpener = ChatDevice Function(String devicePath);

ChatDevice openBootedDevice(String devicePath) =>
    BentosChatDevice(bootLlmDevice(devicePath), devicePath);

/// One entry of the namespace: the path, and either what the device answered
/// about itself or why it could not be asked.
final class DeviceListing {
  const DeviceListing.available(this.id, ChatCapabilities this.capabilities)
      : unavailable = null;

  const DeviceListing.unavailable(this.id, String this.unavailable)
      : capabilities = null;

  /// The device path — the only name a device has here, vendor-blind by
  /// construction.
  final String id;

  /// What the device said about itself, or null when it would not open.
  final ChatCapabilities? capabilities;

  /// Why it would not open, in the words of whoever refused: an unregistered
  /// vendor from the boot table, a missing credential from behind the device.
  final String? unavailable;

  bool get available => capabilities != null;

  @override
  String toString() => available ? id : '$id ($unavailable)';
}

/// The catalog of `/dev/llm` on this machine.
final class DeviceCatalog {
  const DeviceCatalog({
    this.paths = knownDevices,
    this.open = openBootedDevice,
  });

  /// The device paths the bootstrap knows about.
  final List<String> paths;

  /// Injectable for tests and for whoever boots differently.
  final DeviceOpener open;

  /// Every device, in the bootstrap's own order — asked in parallel, since one
  /// device refusing has nothing to do with the next.
  Future<List<DeviceListing>> list() => Future.wait(paths.map(read));

  /// One device, asked directly.
  Future<DeviceListing> read(String path) async {
    try {
      return DeviceListing.available(path, await open(path).capabilities);
    } on Object catch (e) {
      return DeviceListing.unavailable(path, _reason(e));
    }
  }
}

/// The refusal, said in one line — the exception's own words, which already
/// name the vendor that is not registered or the credential that is not there.
String _reason(Object error) {
  final said = error.toString().trim().replaceAll('\n', ' ');
  return said.isEmpty ? error.runtimeType.toString() : said;
}
