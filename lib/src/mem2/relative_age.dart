/// The map's freshness signal — a timestamp rendered as a relative age against
/// an injected clock (`30s`, `5m`, `2h`, `5d`). Pure given the clock. A future
/// timestamp collapses to `now` rather than crashing.
final class RelativeAge {
  const RelativeAge(this.now);

  final DateTime Function() now;

  String of(DateTime timestamp) {
    final d = now().difference(timestamp);
    if (d.isNegative || d.inSeconds < 1) return 'now';
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}
