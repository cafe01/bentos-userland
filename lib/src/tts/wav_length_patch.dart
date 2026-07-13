/// Patches the true WAV lengths into a seekable `-o` file (§5.4-5).
///
/// The device always frames WAV with the streaming-length sentinel
/// (`0xFFFFFFFF` on both the RIFF `ChunkSize` and the `data` subchunk size,
/// tech-spec §3.4) — the only honest value while the stream's total length
/// is unknown mid-flight. When the sink is a real seekable file, the face
/// rewrites those two fields to the truth after the drain. PCM sinks
/// (headerless) and non-seekable sinks (`-o -`, a pipe) are never patched —
/// the sentinel stands, as every serious WAV reader tolerates it.
library;

import 'dart:io';

/// Byte offset of the RIFF `ChunkSize` field — fixed by the WAV container
/// shape (`RIFF` + size(4) + `WAVE`), never chunk-dependent.
const int riffChunkSizeOffset = 4;

/// Walks the WAV subchunks starting after the 12-byte `RIFF...WAVE` header
/// and returns the byte offset of the `data` subchunk's size field — by
/// chunk-walking (id + size + body, padded to even), never a fixed 44-byte
/// assumption, so an extended `fmt` or any chunk ahead of `data` still
/// resolves correctly. Returns `null` when `data` isn't found within
/// [header] — an honest "can't locate", never a guess.
int? locateWavDataSizeOffset(List<int> header) {
  if (header.length < 12) return null;
  var pos = 12;
  while (pos + 8 <= header.length) {
    final id = String.fromCharCodes(header.sublist(pos, pos + 4));
    final size = header[pos + 4] |
        (header[pos + 5] << 8) |
        (header[pos + 6] << 16) |
        (header[pos + 7] << 24);
    if (id == 'data') return pos + 4;
    pos += 8 + size + (size.isOdd ? 1 : 0);
  }
  return null;
}

/// The two honest lengths to write back, derived from [header] and the
/// file's real [totalLength].
class WavLengthPatch {
  const WavLengthPatch({
    required this.riffSizeValue,
    required this.dataSizeOffset,
    required this.dataSizeValue,
  });

  final int riffSizeValue;
  final int dataSizeOffset;
  final int dataSizeValue;

  /// The RIFF `ChunkSize` field offset — always [riffChunkSizeOffset].
  int get riffSizeOffset => riffChunkSizeOffset;
}

/// Computes the patch for a [header] against the file's [totalLength], or
/// `null` when the `data` subchunk can't be located — the sentinel stands
/// rather than risk a wrong offset.
WavLengthPatch? computeWavLengthPatch(List<int> header, int totalLength) {
  final dataSizeOffset = locateWavDataSizeOffset(header);
  if (dataSizeOffset == null) return null;
  final payloadStart = dataSizeOffset + 4;
  final payloadBytes = totalLength - payloadStart;
  if (payloadBytes < 0) return null;
  return WavLengthPatch(
    riffSizeValue: totalLength - 8,
    dataSizeOffset: dataSizeOffset,
    dataSizeValue: payloadBytes,
  );
}

List<int> _u32le(int v) => [
      v & 0xff,
      (v >> 8) & 0xff,
      (v >> 16) & 0xff,
      (v >> 24) & 0xff,
    ];

/// Rewrites the streaming-length sentinels in [file] to the true lengths, in
/// place, after the drain (§5.4-5). A no-op when the header doesn't
/// chunk-walk to a `data` tag — never assumes, never crashes on a foreign
/// file.
Future<void> patchWavFileLengths(File file) async {
  final raf = await file.open(mode: FileMode.append);
  try {
    final totalLength = await raf.length();
    final headerLength = totalLength < 256 ? totalLength : 256;
    await raf.setPosition(0);
    final header = await raf.read(headerLength);
    final patch = computeWavLengthPatch(header, totalLength);
    if (patch == null) return;

    await raf.setPosition(riffChunkSizeOffset);
    await raf.writeFrom(_u32le(patch.riffSizeValue));
    await raf.setPosition(patch.dataSizeOffset);
    await raf.writeFrom(_u32le(patch.dataSizeValue));
  } finally {
    await raf.close();
  }
}
