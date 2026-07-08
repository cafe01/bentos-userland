import 'dart:async';
import 'dart:io';

/// Zone key under which a hermetic home is installed (by `runInMemoryFs`).
const Symbol homeAmbientKey = #bentos.homeAmbient;

/// The logged-in home — the one ambient fact [IOOverrides] does not cover.
///
/// A zone-scoped value when installed, `Platform.environment['HOME']`
/// otherwise; the machine root as the last resort. The mechanism deliberately
/// mirrors [IOOverrides] itself: zone-scoped, invisible at call sites,
/// hermetic under test. No constructor ever carries a home.
String get ambientHome =>
    (Zone.current[homeAmbientKey] as String?) ??
    Platform.environment['HOME'] ??
    '/';
