/// The `live` core — the wire-invariant face over the `LiveTranscription`
/// session machine (§2.3). A long-lived, full-duplex session: audio flows in
/// while the transcript flows out, neither side waiting on the other.
///
/// This is the face seam for the session verb. Two things distinguish it from
/// `transcribe` (§5.4): (1) the feed and the drain run CONCURRENTLY — the
/// full-duplex invariant is structural, `write` never awaits `read`; (2) the
/// projection filters the richer §4.3 union down to the casual register —
/// committed finals only, newline-framed one utterance per line. `partial`
/// (volatile hypotheses) and `correction` (whole-utterance rewrites) are
/// DROPPED: the face emits lines it will not take back, and that honesty lives
/// here, never in the driver. `complete` metadata is `-v`'s job, off the text
/// seam. Path-A today calls the driver object directly; nothing here moves
/// when the byte-wire lands.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:stt_inference/stt_inference.dart';

/// The canonical rate (§3.3) — the ASR lingua franca, kept flag-free.
const _canonicalRate = 16000;

/// The face's PCM-format negotiation asks the user for something only they can
/// supply: which rate the headerless bytes are. The device's accepted [rates]
/// travel with the error so the message can teach instead of just refusing.
final class SttFormatError implements Exception {
  const SttFormatError(this.reason, this.rates);

  final String reason;
  final List<int> rates;

  @override
  String toString() => 'stt: $reason — this device accepts '
      '${rates.join(', ')} Hz; assert one with --rate';
}

/// Resolves the session's PCM triple from the device's capability table (§3.3
/// "negotiated or defaulted"). The default rate is READ from [info], never
/// hardcoded — the device declares its format, the face never guesses:
///
/// - [rate] given: honored as an explicit override; the driver validates it
///   against the table at `STT_SET_PCM_FORMAT` (`EINVAL` if unsupported).
/// - no [rate], canonical (16 kHz) offered: the lingua-franca default, so a
///   canonical source runs `stt live` flag-free.
/// - no [rate], exactly one rate offered: adopt it — the device's sworn format.
/// - no [rate], several rates and no canonical: ambiguous; the face refuses to
///   choose the user's audio for them and demands `--rate`.
///
/// Encoding is S16LE (the subsystem's one encoding) and channels mono — both
/// always in-table for a recon provider; a stereo/encoding knob joins `--rate`
/// only if a provider ever forces the fork.
PcmTriple negotiateLiveTriple(LiveTranscriptionInfo info, {int? rate}) {
  final resolved = rate ?? _defaultRate(info);
  return PcmTriple(
    rate: resolved,
    encoding: PcmEncoding.s16le,
    channels: 1,
  );
}

int _defaultRate(LiveTranscriptionInfo info) {
  if (info.pcmRates.contains(_canonicalRate)) return _canonicalRate;
  if (info.pcmRates.length == 1) return info.pcmRates.single;
  throw SttFormatError(
      'this device offers several PCM rates and none is the 16 kHz default',
      info.pcmRates);
}

/// Drives one live session over [driver]: relays [audioIn] as audio writes on
/// one side while projecting committed finals from [driver]'s output to [out]
/// on the other. The two loops run concurrently and never serialize.
///
/// Before the first write (in `IDLE`) the face negotiates the PCM triple: it
/// reads `STT_GET_INFO` and, via [negotiateLiveTriple], resolves the rate from
/// the device's table or the explicit [rate] override, then asserts it with
/// `STT_SET_PCM_FORMAT`. An override the device rejects surfaces as an
/// [SttFormatError] naming the accepted rates — the honest failure lands while
/// the consumer can still react, never mid-stream.
///
/// [audioIn] reaching EOF becomes `STT_INPUT_END` (§2.3 DRAINING): the driver
/// commits pending partials to finals and ends the stream. A session with no
/// audio is legitimate — it drains immediately to EOF with no output. [language]
/// issues `STT_SET_LANGUAGE` before the first write (valid only in `IDLE`).
/// Under [verbose], the `complete` run metadata is printed to [err] — off the
/// text seam. A [DriverError] or [SttFormatError] propagates to the caller.
Future<void> runLive(
  LiveTranscriptionDriver<Object?> driver, {
  required Stream<List<int>> audioIn,
  required IOSink out,
  IOSink? err,
  String? language,
  int? rate,
  bool verbose = false,
}) async {
  err ??= stderr;
  final session = await driver.open();
  try {
    final info = await session.ioctl('STT_GET_INFO') as LiveTranscriptionInfo;
    final triple = negotiateLiveTriple(info, rate: rate);
    try {
      await session.ioctl('STT_SET_PCM_FORMAT', triple);
    } on DriverError catch (e) {
      // The default is table-derived and always valid, so the only triple the
      // device refuses here is an explicit --rate override outside the table.
      if (e.errno == 22) {
        throw SttFormatError('rate ${triple.rate} Hz is not supported',
            info.pcmRates);
      }
      rethrow;
    }
    if (language != null && language.isNotEmpty) {
      await session.ioctl('STT_SET_LANGUAGE', language);
    }

    // Feed side: relay audio verbatim, then assert input-end on EOF (§5.4
    // seam 1). Never touches the read side.
    Future<void> feed() async {
      await for (final chunk in audioIn) {
        if (chunk.isEmpty) continue;
        await session.write(Uint8List.fromList(chunk));
      }
      await session.inputEnd();
    }

    // Drain side: project the typed union to the casual register. Runs while
    // audio is still flowing — this concurrency IS the full-duplex invariant.
    Future<void> drain() async {
      while (true) {
        final event = await session.read();
        if (event == null) break;
        switch (event) {
          case LiveFinal(:final segment):
            out.writeln(segment.text); // one committed utterance, one line
          case LiveComplete(:final metadata):
            if (verbose) {
              final lang = metadata.detectedLanguage;
              err!.writeln(
                '[${metadata.model}'
                '${lang != null ? ' · $lang' : ''}'
                ' · ${metadata.audioDurationMs}ms audio'
                ' · ${metadata.timingMs}ms]',
              );
            }
          case Partial():
          case Correction():
            break; // volatile / rewrite — never crosses the casual text seam
        }
      }
    }

    await Future.wait([feed(), drain()]);
  } finally {
    await session.close();
  }
}
