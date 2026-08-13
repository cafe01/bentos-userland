/// The layer no other test in this suite can see.
///
/// Every other input test injects a synthetic [KeyboardEvent] straight into
/// the component tree, which enters *below* nocterm's `TerminalBinding` and
/// therefore below its `_batchCharacterEvents` — the exact place where a real
/// terminal's Enter is destroyed. A green suite there proves nothing about a
/// person typing.
///
/// So this file feeds **raw bytes** through the real binding, over a
/// [TerminalBackend] whose input stream the test controls. One `feed` is one
/// stdin read, and that is the whole variable under test: the same bytes
/// split across two reads used to send, and delivered in one read did not.
///
/// One binding for the file, re-attached per case: `TerminalBinding` is a
/// process-wide singleton, and its VM service extensions cannot be
/// unregistered, so a second one cannot be built in the same process.
library;

import 'dart:async';

import 'package:bentos_userland/src/chat/handle.dart';
import 'package:bentos_userland/src/chat_client/app.dart';
import 'package:bentos_userland/src/chat_client/render/screen_view.dart';
import 'package:bentos_userland/src/chat_client/ticker.dart' as chat show Ticker;
import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

import 'fake_channel.dart';

final _alfred = Handle('alfred', 'bentos.life');

final class _NullTicker implements chat.Ticker {
  @override
  Stream<void> get ticks => const Stream.empty();

  @override
  void nudge() {}

  @override
  void dispose() {}

  @override
  bool get connected => true;
}

/// A backend whose input stream is the test's own — every [feed] is exactly
/// one stdin read, so the test can say whether bytes arrived together or
/// apart. Output is discarded: nothing here asserts on pixels.
final class _ByteBackend implements TerminalBackend {
  final _input = StreamController<List<int>>.broadcast();

  void feed(String s) => _input.add(s.codeUnits);

  @override
  Stream<List<int>>? get inputStream => _input.stream;

  @override
  Size getSize() => const Size(80, 24);

  @override
  bool get supportsSize => true;

  @override
  Stream<Size>? get resizeStream => null;

  @override
  Stream<void>? get shutdownStream => null;

  @override
  bool get isAvailable => true;

  @override
  void writeRaw(String data) {}

  @override
  void enableRawMode() {}

  @override
  void disableRawMode() {}

  @override
  void requestExit([int exitCode = 0]) {}

  @override
  void notifySizeChanged(Size newSize) {}

  @override
  void dispose() {
    unawaited(_input.close());
  }
}

/// Lets the binding's input listener and frame scheduler run.
Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late _ByteBackend backend;
  late TerminalBinding binding;

  setUpAll(() {
    backend = _ByteBackend();
    binding = TerminalBinding(Terminal(backend));
    binding.initialize();
    unawaited(binding.runEventLoop());
  });

  tearDownAll(() {
    binding.shutdown();
    backend.dispose();
  });

  /// A fresh client on the standing binding.
  Future<({ChatProgram program, FakeChannel channel})> stand() async {
    final channel = FakeChannel(name: 'fabrica', me: _alfred);
    final program = ChatProgram(
      channels: [channel],
      ticker: _NullTicker(),
      floor: FakeChatFloor(),
      place: '/fake/place',
    );
    binding.attachRootComponent(ChatApp(program: program));
    await _settle();
    return (program: program, channel: channel);
  }

  group('bytes through the real binding — one read versus two', () {
    test('prose and CR in separate reads sends', () async {
      final s = await stand();

      backend.feed('status?');
      await _settle();
      backend.feed('\r');
      await _settle();

      expect(s.channel.spoken, ['status?']);
      expect(s.program.session.currentRoom.composer.text, '');
    });

    test('prose and CR in ONE read also sends — the coalescing case', () async {
      final s = await stand();

      // One stdin read. This is what a real terminal delivers whenever bytes
      // land while the screen is redrawing — fast typing, key repeat, paste.
      backend.feed('status?\r');
      await _settle();

      expect(s.channel.spoken, ['status?']);
      expect(s.program.session.currentRoom.composer.text, '');
    });

    test('a block of lines in one read speaks each line', () async {
      final s = await stand();

      backend.feed('first\rsecond\rtrailing');
      await _settle();

      expect(s.channel.spoken, ['first', 'second']);
      expect(s.program.session.currentRoom.composer.text, 'trailing');
    });
  });
}
