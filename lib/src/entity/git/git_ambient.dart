import 'dart:async';

import 'git.dart';
import 'process_git.dart';

/// Zone key under which a hermetic [Git] port is installed.
const Symbol gitAmbientKey = #bentos.gitAmbient;

/// The Git port in force — a zone-scoped value when installed, the real
/// subprocess otherwise.
///
/// The mechanism deliberately mirrors `IOOverrides` and `Place`'s
/// `ambientHome`: zone-scoped, invisible at call sites, hermetic under test.
/// **No constructor ever carries a port.** `Entity(name)` is a bare handle,
/// and a test that wants a double installs it around the code under test
/// rather than injecting it through every type in the graph.
Git get ambientGit => (Zone.current[gitAmbientKey] as Git?) ?? const ProcessGit();

/// Runs [body] with [git] installed as the ambient port.
R runWithGit<R>(Git git, R Function() body) =>
    runZoned(body, zoneValues: {gitAmbientKey: git});

/// Runs an asynchronous [body] with [git] installed as the ambient port.
Future<R> runWithGitAsync<R>(Git git, Future<R> Function() body) =>
    runZoned(body, zoneValues: {gitAmbientKey: git});
