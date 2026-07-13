/// The `synthesize` core — the wire-invariant face over the `SpeechSynthesis`
/// job machine (§2.4). Text in → audio bytes out; one job, then EOF.
///
/// This is the face seam consolidated (§5.4): [textIn] reaching EOF becomes
/// `TTS_INPUT_END` on the device (seam 1). Unlike `transcribe`, there is no
/// typed register to project (§4.4) — the output IS the audio byte stream,
/// already framed by the base (streaming-WAV header rides the first chunk), so
/// the face relays bytes verbatim. Path-A today calls the driver object
/// directly; nothing here moves when the byte-wire lands.
library;

import 'dart:convert';
import 'dart:io';

import 'package:bentos_driver_sdk/bentos_driver_sdk.dart' show DriverError;
import 'package:tts_inference/tts_inference.dart';

import 'feedback.dart';

/// A `--voice`/`--speed`/`--format` proposal the device rejected at the config
/// ioctl (§3.1: `EINVAL` at the ioctl, before any text flows) — a
/// user-correctable format/config error, distinct from an infrastructure
/// [DriverError]. Carries the driver's teaching message so the face maps it to
/// `EX_USAGE`. Twin of `stt`'s `SttFormatError`.
class TtsFormatError implements Exception {
  final String message;
  const TtsFormatError(this.message);
  @override
  String toString() => message;
}

/// Drives one synthesis job over [driver]: relays [textIn] as text writes,
/// asserts input-end at EOF, and streams the audio bytes to [out].
///
/// [voice]/[speed]/[format] descend as `TTS_SET_*` ioctls in `IDLE` before the
/// first write (§2.5-1); a proposal outside the capability table surfaces as a
/// [TtsFormatError] (user-correctable), never a bare [DriverError]. [format]
/// unset takes the class default (streaming WAV at the provider's triple).
///
/// Bytes are UTF-8 decoded across chunk boundaries by the streaming decoder —
/// a multibyte char split by a stdin chunk is buffered, never corrupted. Under
/// [feedbackEnabled] (§5.4-6), the resolved beat (model · format · voice, read
/// from `TTS_GET_INFO` — no new device surface, §4.4/§5.3) and the completion
/// beat (bytes · wall-clock) print to [err]; the intent beat is the command's
/// job, before the device opens. A [DriverError] (EACCES with no credential,
/// provider failure) propagates.
Future<void> runSynthesize(
  SpeechSynthesisDriver driver, {
  required Stream<List<int>> textIn,
  required IOSink out,
  IOSink? err,
  String? voice,
  double? speed,
  TtsOutputFormat? format,
  bool feedbackEnabled = false,
}) async {
  err ??= stderr;
  final session = await driver.open();
  final watch = feedbackEnabled ? (Stopwatch()..start()) : null;
  var bytesOut = 0;
  try {
    // Config in IDLE (§2.5-1): a rejection here is a user-correctable proposal,
    // surfaced as TtsFormatError — never conflated with an infra DriverError.
    try {
      if (voice != null) await session.ioctl('TTS_SET_VOICE', voice);
      if (speed != null) await session.ioctl('TTS_SET_SPEED', speed);
      if (format != null) await session.ioctl('TTS_SET_OUTPUT_FORMAT', format);
    } on DriverError catch (e) {
      throw TtsFormatError('tts: $e');
    }

    if (feedbackEnabled) {
      final info = await session.ioctl('TTS_GET_INFO') as SpeechSynthesisInfo;
      err.writeln(ttsResolvedLine(
        model: info.model,
        format: ttsFormatLabel(format),
        voice: voice,
      ));
    }

    // Feed: decode text bytes to string records; the decoder buffers partial
    // multibyte sequences across chunk seams.
    await for (final text in textIn.transform(utf8.decoder)) {
      if (text.isEmpty) continue;
      await session.write(text);
    }
    // EOF on the face → TTS_INPUT_END on the device (§5.4 seam 1).
    await session.inputEnd();

    // Drain: relay the audio byte stream verbatim (§4.4 — bytes, not records).
    while (true) {
      final chunk = await session.read();
      if (chunk == null) break;
      out.add(chunk);
      bytesOut += chunk.length;
    }

    if (watch != null) {
      err.writeln(ttsCompletionLine(bytes: bytesOut, elapsed: watch.elapsed));
    }
  } finally {
    await session.close();
  }
}
