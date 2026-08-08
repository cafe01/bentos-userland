/// The salience dial as a value type: an eleven-notch scale from `0.0` to
/// `1.0` in tenths, carried as an integer `0..10`.
///
/// No float comparison exists anywhere in the organ — parse maps the decimal
/// form onto a notch, everything downstream is integral, and the inclusive
/// band bounds are therefore exact rather than approximately exact.
final class Attention implements Comparable<Attention> {
  const Attention._(this.tenths);

  /// The notch, `0..10`. `7` renders `0.7`, `10` renders `1.0`.
  final int tenths;

  /// The full closed range, `0.0` and `1.0` inclusive.
  static const minTenths = 0;
  static const maxTenths = 10;

  /// Construct from an integer notch; throws [RangeError] off-scale.
  factory Attention.ofTenths(int tenths) {
    if (tenths < minTenths || tenths > maxTenths) {
      throw RangeError.range(tenths, minTenths, maxTenths, 'tenths');
    }
    return Attention._(tenths);
  }

  static final _notch = RegExp(r'^(0\.\d|1\.0)$');

  /// The value assumed for a page whose attention could not be read at all —
  /// missing, or off-grammar past what [parse] accepts. Cold-ward on purpose:
  /// an unread band is not evidence the page earned a warm or hot mind, so the
  /// guess must never be able to inflate a page into standing salience nobody
  /// elected. `0.5` is the coolest notch a plain reach still surfaces without
  /// a deliberate `--cold`; this default may be lowered but never raised.
  static final assumedDefault = Attention._(5);

  /// Parse the decimal form (`0.0`–`1.0`), and the near-misses that mean the
  /// same thing to anyone but a YAML parser: a bare integer (`0`, `1`), a
  /// leading-dot fraction (`.7`), a trailing zero (`0.70`), a quoted scalar
  /// (`"0.7"`), and surrounding whitespace. A field whose accepted grammar is
  /// narrower than what it emits is a defect on its face, so this accepts
  /// everything [render] could plausibly meet on disk. Only genuinely
  /// off-notch magnitude (`0.75`, `1.1`, `-0.1`) is a [FormatException].
  factory Attention.parse(String source) {
    var s = source.trim();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1).trim();
    }
    if (s == '0' || s == '1') s = '$s.0';
    if (s.startsWith('.')) s = '0$s';
    final trailingZeros = RegExp(r'^(0\.\d)0+$').firstMatch(s);
    if (trailingZeros != null) s = trailingZeros.group(1)!;
    if (!_notch.hasMatch(s)) {
      throw FormatException('off-notch attention: "$source" (expected 0.0–1.0 in 0.1 steps)');
    }
    return Attention._(s == '1.0' ? 10 : int.parse(s.substring(2)));
  }

  static final _delta = RegExp(r'^([+-]?)([01])\.(\d)$');

  /// Parse a signed `--by` delta into notch-tenths (`-0.3` → -3, `0.2` → 2).
  /// Off-notch magnitude (`0.75`, `1.5`) is a [FormatException] — the delta
  /// rides the same eleven-notch scale as the dial it moves.
  static int parseDelta(String source) {
    final m = _delta.firstMatch(source.trim());
    if (m == null) {
      throw FormatException('off-notch delta: "$source" (expected ±0.0–1.0 in 0.1 steps)');
    }
    final magnitude = int.parse(m.group(2)!) * 10 + int.parse(m.group(3)!);
    if (magnitude > maxTenths) {
      throw FormatException('off-notch delta: "$source" (magnitude exceeds 1.0)');
    }
    return m.group(1) == '-' ? -magnitude : magnitude;
  }

  /// Render back to the exact decimal form.
  String render() => tenths == 10 ? '1.0' : '0.$tenths';

  /// Clamped addition of a signed [deltaTenths]. Saturates at both rails and
  /// reports whether it clamped — the visible-clamp `--by` needs.
  (Attention, bool) adjust(int deltaTenths) {
    final raw = tenths + deltaTenths;
    final clamped = raw.clamp(minTenths, maxTenths);
    return (Attention._(clamped), clamped != raw);
  }

  @override
  int compareTo(Attention other) => tenths.compareTo(other.tenths);

  @override
  bool operator ==(Object other) => other is Attention && other.tenths == tenths;

  @override
  int get hashCode => tenths.hashCode;

  @override
  String toString() => render();
}
