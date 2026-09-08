import 'dart:io';

import 'package:bentos_userland/src/git/model/commit.dart';
import 'package:bentos_userland/src/mem/bank.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../entity/helpers.dart';

/// A git work tree named [name] under the site, with a first commit on
/// `main` unless [born] is false. No Entity.
Directory standBank(Site site, String name, {bool born = true}) {
  final where = Directory(p.join(site.root.path, name))..createSync();
  final init = Process.runSync(
    'git',
    ['init', '--quiet', '--initial-branch=main', where.path],
  );
  expect(init.exitCode, 0, reason: '${init.stderr}');
  if (born) {
    final commit = Process.runSync(
      'git',
      ['-C', where.path, 'commit', '--allow-empty', '--quiet', '-m', 'born'],
      environment: {
        'GIT_AUTHOR_NAME': testActor.name,
        'GIT_AUTHOR_EMAIL': testActor.email,
        'GIT_COMMITTER_NAME': testActor.name,
        'GIT_COMMITTER_EMAIL': testActor.email,
      },
    );
    expect(commit.exitCode, 0, reason: '${commit.stderr}');
  }
  return where;
}

/// A super-repo gitlink named [name] and no checkout — registered, invisible.
void standGitlinkOnly(Site site, String name) {
  site.git.stageGitlink(
    site.root.path,
    path: name,
    at: Commit('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
  );
}

Bank resolved(Site site, String name) {
  final resolution = Bank.resolve(name, vantage: site.root.path);
  expect(resolution, isA<Found>(), reason: 'expected $name at ${site.root.path}');
  return (resolution as Found).bank;
}
