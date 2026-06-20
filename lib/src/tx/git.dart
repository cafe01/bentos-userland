import 'dart:io';

/// A failure running a git command on a tx store.
final class TxGitError extends Error {
  TxGitError(this.message);
  final String message;
  @override
  String toString() => 'tx: $message';
}

/// Run git with [args] in [dir]. Throws [TxGitError] on nonzero exit.
Future<void> git(Directory dir, List<String> args) async {
  final result = await Process.run(
    'git',
    ['-C', dir.path, ...args],
    stdoutEncoding: null,
    stderrEncoding: null,
  );
  if (result.exitCode != 0) {
    final err = String.fromCharCodes(result.stderr as List<int>).trim();
    throw TxGitError('git ${args.join(' ')} failed: $err');
  }
}

/// Like [git] but returns decoded stdout.
Future<String> gitOut(Directory dir, List<String> args) async {
  final result = await Process.run('git', ['-C', dir.path, ...args]);
  if (result.exitCode != 0) {
    final err = (result.stderr as String).trim();
    throw TxGitError('git ${args.join(' ')} failed: $err');
  }
  return result.stdout as String;
}
