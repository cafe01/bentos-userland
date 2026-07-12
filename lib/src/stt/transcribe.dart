/// The `transcribe` core — the wire-invariant face over the `Transcription`
/// job machine (§2.2). Audio in → transcript out; one job, then EOF.
///
/// This is the whole face seam consolidated (§5.4): [audioIn] reaching EOF
/// becomes `STT_INPUT_END` on the device (seam 1), and the projection filters
/// the typed event union down to the casual register — committed segment text
/// only, `complete` metadata dropped from the text stream (it is `-v`'s job,
/// never the transcript's). Path-A today calls the driver object directly;
/// nothing here moves when the byte-wire lands.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:stt_inference/stt_inference.dart';

/// Drives one transcribe job over [driver]: relays [audioIn] as audio writes,
/// asserts input-end at EOF, and projects the transcript to [out].
///
/// [language] issues `STT_SET_LANGUAGE` before the first write (valid only in
/// `IDLE`, §2.5-1). Under [verbose], the `complete` run metadata is printed to
/// [err] — off the text seam. A [DriverError] (e.g. EACCES with no credential,
/// EINVAL on empty audio) propagates to the caller.
Future<void> runTranscribe(
  TranscriptionDriver driver, {
  required Stream<List<int>> audioIn,
  required IOSink out,
  IOSink? err,
  String? language,
  bool verbose = false,
}) async {
  err ??= stderr;
  final session = await driver.open();
  try {
    if (language != null && language.isNotEmpty) {
      await session.ioctl('STT_SET_LANGUAGE', language);
    }
    // Feed: relay audio bytes verbatim (container sniffed at the first write).
    await for (final chunk in audioIn) {
      if (chunk.isEmpty) continue;
      await session.write(Uint8List.fromList(chunk));
    }
    // EOF on the face → STT_INPUT_END on the device (§5.4 seam 1).
    await session.inputEnd();

    // Drain: project the typed union to the casual register.
    while (true) {
      final event = await session.read();
      if (event == null) break;
      switch (event) {
        case TranscriptionSegmentEvent(:final segment):
          out.write(segment.text);
        case TranscriptionComplete(:final metadata):
          if (verbose) {
            final lang = metadata.detectedLanguage;
            err.writeln(
              '[${metadata.model}'
              '${lang != null ? ' · $lang' : ''}'
              ' · ${metadata.audioDurationMs}ms audio'
              ' · ${metadata.timingMs}ms]',
            );
          }
      }
    }
    out.writeln(); // userland trailing newline after the transcript
  } finally {
    await session.close();
  }
}
