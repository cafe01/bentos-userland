/// Was I named — the layer's entire doing, since the medium routes nothing
/// and knows no recipients.
library;

import 'handle.dart';

/// Scans a body for `@handle` mentions of one reader, plus the `all` word
/// that names everyone.
///
/// Matching is case-insensitive: a handle typed as `@Alfred` still names
/// `@alfred`, since prose is typed by a person and not by a machine that
/// remembers the exact case a handle registered under — there is no
/// registration to remember it against anyway.
final class MentionScanner {
  const MentionScanner(this.me, {this.allWord = 'all'});

  final Handle me;
  final String allWord;

  static final _token = RegExp(r'@([A-Za-z0-9_.\-]+)');

  /// True when [body] names this reader directly, or names everyone.
  bool mentions(String body) {
    final mine = me.local.toLowerCase();
    final all = allWord.toLowerCase();
    for (final match in _token.allMatches(body)) {
      final token = match.group(1)!.toLowerCase();
      if (token == mine || token == all) return true;
    }
    return false;
  }
}
