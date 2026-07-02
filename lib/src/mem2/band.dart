/// The attention bands — a heatmap of the salience dial. Each band is a closed
/// range over the eleven-notch scale (integer tenths); the four bands plus the
/// vanishing point `0.0` **partition** the scale, so every legal notch above
/// zero belongs to exactly one band. The single source for the thresholds.
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
