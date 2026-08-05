/// The `stt` and `tts` boot layers are the same pure routing as `llm`'s, and
/// their routing errors are read by the same person: someone who typed a device
/// path at a shell. These assertions pin the register — the message names the
/// device asked for and the vendors reachable, and never sends the reader into
/// the package's own source to wire a driver.
library;

import 'package:bentos_userland/boot_stt.dart';
import 'package:bentos_userland/boot_tts.dart';
import 'package:test/test.dart';

void expectSpeaksToTheUser(String message, String devicePath, String vendor) {
  expect(message, contains(devicePath));
  expect(message, contains(vendor));
  expect(message, contains('vendors'));

  expect(message, isNot(contains('register')));
  expect(message, isNot(contains('.dart')));
  expect(message, isNot(contains('bin/')));
  expect(message, isNot(contains('lib/')));
}

void main() {
  test('stt transcribe: unknown vendor speaks to the user', () {
    try {
      bootTranscribeDevice('/dev/stt/cohere/whisper/transcribe');
      fail('expected a routing error');
    } on SttBootException catch (e) {
      expectSpeaksToTheUser(
        e.message,
        '/dev/stt/cohere/whisper/transcribe',
        'cohere',
      );
    }
  });

  test('stt live: unknown vendor speaks to the user', () {
    try {
      bootLiveDevice('/dev/stt/cohere/whisper/live');
      fail('expected a routing error');
    } on SttBootException catch (e) {
      expectSpeaksToTheUser(e.message, '/dev/stt/cohere/whisper/live', 'cohere');
    }
  });

  test('tts: unknown vendor speaks to the user', () {
    try {
      bootTtsDevice('/dev/tts/cohere/voice');
      fail('expected a routing error');
    } on TtsBootException catch (e) {
      expectSpeaksToTheUser(e.message, '/dev/tts/cohere/voice', 'cohere');
    }
  });
}
