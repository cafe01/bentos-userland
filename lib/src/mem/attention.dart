/// The attention bands — a heatmap of the salience dial. Each band is a
/// closed range over the eleven-notch scale (integer tenths); the four bands
/// plus the vanishing point `0.0` **partition** the scale, so every legal
/// notch above zero belongs to exactly one band. The single source for the
/// thresholds.
enum Band {
  hot(10, 10),
  warm(7, 9),
  cool(4, 6),
  cold(1, 3);

  const Band(this.minTenths, this.maxTenths);

  /// The inclusive range of the band, in integer tenths.
  final int minTenths;
  final int maxTenths;

  /// Resolve a band by name; an out-of-table name is an error.
  static Band parse(String name) => Band.values.firstWhere(
        (b) => b.name == name,
        orElse: () => throw FormatException('unknown band: "$name"'),
      );
}

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

  /// Construct from a decimal value, rounded to the nearest notch — the
  /// forgiving entry point for a caller holding a `double` rather than
  /// on-disk text. `0.7`, and `0.70000000000000001` a float literal can
  /// actually produce, both land on notch 7. Throws [RangeError] off-scale.
  factory Attention(double value) {
    final t = (value * 10).round();
    if (t < minTenths || t > maxTenths) {
      throw RangeError.range(t, minTenths, maxTenths, 'value');
    }
    return Attention._(t);
  }

  static final _notch = RegExp(r'^(0\.\d|1\.0)$');

  /// The value assumed for a page whose attention could not be read at all —
  /// missing, or off-grammar past what [parse] accepts. Cold-ward on
  /// purpose: an unread band is not evidence the page earned a warm or hot
  /// mind, so the guess must never be able to inflate a page into standing
  /// salience nobody elected. `0.5` is the coolest notch a plain reach still
  /// surfaces without a deliberate `--cold`; this default may be lowered but
  /// never raised.
  static const assumedDefault = Attention._(5);

  /// Parse the decimal form (`0.0`–`1.0`), and the near-misses that mean the
  /// same thing to anyone but a YAML parser: a bare integer (`0`, `1`), a
  /// leading-dot fraction (`.7`), a trailing zero (`0.70`), a quoted scalar
  /// (`"0.7"`), and surrounding whitespace. A field whose accepted grammar is
  /// narrower than what it emits is a defect on its face, so this accepts
  /// everything [render] could plausibly meet on disk. Only genuinely
  /// off-notch magnitude (`0.75`, `1.1`, `-0.1`) is a [FormatException].
  static Attention parse(String source) {
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

  /// The decimal value, `0.0..1.0`.
  double get value => tenths / 10;

  /// The band this notch falls in. `0.0` falls in no band — the vanishing
  /// point [Band] deliberately does not cover — so it is the one notch this
  /// getter cannot answer for.
  Band get band => Band.values.firstWhere(
        (b) => tenths >= b.minTenths && tenths <= b.maxTenths,
        orElse: () => throw StateError('0.0 carries no band'),
      );

  /// Render back to the exact decimal form.
  String render() => tenths == 10 ? '1.0' : '0.$tenths';

  @override
  int compareTo(Attention other) => tenths.compareTo(other.tenths);

  @override
  bool operator ==(Object other) => other is Attention && other.tenths == tenths;

  @override
  int get hashCode => tenths.hashCode;

  @override
  String toString() => render();
}
