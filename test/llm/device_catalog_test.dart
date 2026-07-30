// The one enumeration of /dev/llm: names from the bootstrap, capabilities from
// the devices themselves — and a device that will not open says why.

import 'package:bentos_userland/boot.dart';
import 'package:bentos_userland/bundled_drivers.dart';
import 'package:bentos_userland/llm.dart';
import 'package:chat_inference/chat_inference.dart';
import 'package:test/test.dart';

void main() {
  setUp(clearLlmDrivers);
  tearDown(clearLlmDrivers);

  test('reads each device its own capabilities, never a table', () async {
    registerBundledLlmDrivers();
    const catalog = DeviceCatalog(paths: ['/dev/llm/fixture/weather']);

    final listing = (await catalog.list()).single;

    expect(listing.id, '/dev/llm/fixture/weather');
    expect(listing.available, isTrue);
    // The fixture driver's own word, and nothing this catalog could have made
    // up: the model is the scenario.
    expect(listing.capabilities!.model, 'weather');
    expect(listing.capabilities!.provider, 'fixture');
    expect(listing.capabilities!.supportsFunctions, isTrue);
  });

  test('lists a device it cannot open, carrying the refusal', () async {
    registerBundledLlmDrivers();
    const catalog = DeviceCatalog(
      paths: ['/dev/llm/fixture/echo', '/dev/llm/cohere/command'],
    );

    final listed = await catalog.list();

    expect(listed.map((d) => d.id),
        ['/dev/llm/fixture/echo', '/dev/llm/cohere/command'],
        reason: 'the enumeration is the bootstrap order, refusals included');
    expect(listed.first.available, isTrue);
    expect(listed.last.available, isFalse);
    expect(listed.last.unavailable, contains('cohere'),
        reason: 'the reason is the refusal in its own words');
  });

  test('a vendor with no driver registered is unavailable, not absent', () async {
    const catalog = DeviceCatalog(paths: knownDevices);

    final listed = await catalog.list();

    expect(listed.length, knownDevices.length);
    expect(listed.every((d) => !d.available), isTrue,
        reason: 'nothing is registered: every device refuses to open');
    expect(listed.map((d) => d.id), knownDevices);
  });

  test('the loopback is part of what the bootstrap knows', () async {
    registerBundledLlmDrivers();

    final listed = await const DeviceCatalog().list();
    final loopback = listed.where((d) => d.id.startsWith('/dev/llm/fixture/'));

    expect(loopback, isNotEmpty);
    expect(loopback.every((d) => d.available), isTrue,
        reason: 'the loopback asks for no credential, anywhere, for anyone');
  });

  test('a device is asked through whatever opener it is given', () async {
    var asked = <String>[];
    final catalog = DeviceCatalog(
      paths: const ['/dev/llm/vendor/model'],
      open: (path) {
        asked.add(path);
        return _StubDevice(path);
      },
    );

    final listing = (await catalog.list()).single;

    expect(asked, ['/dev/llm/vendor/model']);
    expect(listing.capabilities!.model, 'stub');
  });
}

class _StubDevice implements ChatDevice {
  _StubDevice(this.devicePath);

  @override
  final String devicePath;

  @override
  Future<ChatCapabilities> get capabilities async => const ChatCapabilities(
        model: 'stub',
        provider: 'stub',
        maxContextTokens: 1,
        maxOutputTokens: 1,
        reasoningSupport: ReasoningSupport.none,
        supportsFunctions: false,
        supportedMimeTypes: [],
        supportsStreaming: false,
        supportedInputFormats: ['unstructured'],
        supportedOutputFormats: ['unstructured'],
        supportedStopReasons: ['end_turn'],
      );

  @override
  Stream<ChatEvent> infer(List<ChatMessage> messages, [ChatIOConfig config = const ChatIOConfig()]) =>
      const Stream.empty();
}
