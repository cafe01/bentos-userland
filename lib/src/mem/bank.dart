import 'dart:io';

import 'package:path/path.dart' as p;

import '../entity/action.dart' as ent;
import '../git/git_ambient.dart';
import '../git/model/actor.dart';
import 'page.dart';

/// The store, and the only component of `mem/` that speaks to it. Resolves a
/// name from a vantage, reads the tree in place, lands writes as acts, and
/// brings the tree to the landed line.
///
/// **No Entity, no Place.lookup, no Things CLI.** [resolve] walks up from the
/// vantage and takes a git work tree whose directory name — or a super-repo
/// gitlink's path basename — matches the candidate. Reads are in place
/// (`pages()`, `page()`); writes are never a silent overwrite of a person's
/// edits (`land()`), and reconciling the tree afterwards is `advance()`.
final class Bank {
  Bank._({
    required this.name,
    required this.vantage,
    required Directory address,
    required bool treeStands,
  })  : _address = address,
        _treeStands = treeStands;

  /// The vantage this bank was resolved from, carried so that a walk opening
  /// a foreign bank opens it from the same one without being told.
  final String vantage;

  /// The instance a bank is: house convention, ratified — a bank has exactly
  /// one line, and it is this one.
  static const String mainInstanceId = 'main';

  /// The suffix a bank's entity name carries: the ontology's, not the being's.
  /// A call may name the being — `alfred` — while the tree standing beside
  /// it is `alfred.mem`, which is why [resolve] may not take the name it is
  /// given as the last word.
  static const String suffix = '.mem';

  final String name;
  final Directory _address;
  final bool _treeStands;

  /// Resolves a bank by walking up from [vantage]. The only place a bank
  /// name becomes a thing on disk.
  ///
  /// **Exactly as given first, then with [suffix] appended.** `-b alfred`
  /// names the being, never the tree, so a lookup that took the name
  /// verbatim and stopped left every default unreachable and made
  /// `-b alfred.mem` the only working form. Exact-first keeps a tree
  /// literally named `x.mem` — or any tree whose name is its own whole
  /// truth — winning its own name before the fallback is ever tried.
  static Resolution resolve(String name, {required String vantage}) {
    final tried = <String>[
      name,
      if (!name.endsWith(suffix)) '$name$suffix',
    ];
    for (final candidate in tried) {
      final found = _open(candidate, vantage: vantage);
      if (found != null) return Found(found);
    }
    return NotFound(tried, vantage);
  }

  /// One lookup, or null where no work tree and no gitlink answers [name]
  /// on the walk up from [vantage].
  static Bank? _open(String name, {required String vantage}) {
    var dir = Directory(p.normalize(vantage));
    while (true) {
      final child = Directory(p.join(dir.path, name));
      if (_isWorktreeRoot(child.path)) {
        return Bank._(
          name: name,
          vantage: vantage,
          address: child,
          treeStands: true,
        );
      }
      if (_isWorktreeRoot(dir.path) && p.basename(dir.path) == name) {
        return Bank._(
          name: name,
          vantage: vantage,
          address: dir,
          treeStands: true,
        );
      }
      if (_isWorktreeRoot(dir.path) && _gitlinkNamed(dir.path, name)) {
        return Bank._(
          name: name,
          vantage: vantage,
          address: Directory(p.join(dir.path, name)),
          treeStands: false,
        );
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  static bool _isWorktreeRoot(String path) {
    if (!Directory(path).existsSync()) return false;
    final top = ambientGit.topLevel(path);
    if (top == null) return false;
    return _canonical(top) == _canonical(path);
  }

  static bool _gitlinkNamed(String workTree, String name) {
    if (ambientGit.stagedGitlink(workTree, name) != null) return true;
    for (final entry in ambientGit.stagedEntries(workTree, '')) {
      if (entry.mode == '160000' && p.basename(entry.path) == name) {
        return true;
      }
    }
    return false;
  }

  static String _canonical(String path) {
    final dir = Directory(path);
    return dir.existsSync() ? dir.resolveSymbolicLinksSync() : path;
  }

  /// Whether a tree of this bank stands, so a reader can tell "empty" from
  /// "invisible" before asking [pages] or [page] — both answer `[]`/`null`
  /// either way, which is honest about *what came back* and silent about
  /// *why*. A caller that means to report the difference checks this first.
  bool get hasTree => _treeStands && _isWorktreeRoot(_address.path);

  /// The address a tree of this bank would stand at, whether or not one
  /// does — what a "no tree" reader message names.
  Directory get materializationAddress => _address;

  Directory? get _root => hasTree ? _address : null;

  /// Every page of the bank, read from the working tree with ordinary file
  /// IO. A bank with no working tree materialized has no pages, and says so
  /// with an empty list — indistinguishable from a bank that has a tree and
  /// genuinely holds nothing. A caller that must tell the two apart checks
  /// [hasTree] first; this method does not.
  List<Page> pages() {
    final root = _root;
    if (root == null) return const [];
    return [
      for (final file in _markdownFiles(root))
        Page.parse(_topicOf(root, file), file.readAsStringSync()),
    ];
  }

  Page? page(String topic) {
    final root = _root;
    if (root == null) return null;
    final file = File(p.join(root.path, '$topic.md'));
    if (!file.existsSync()) return null;
    return Page.parse(topic, file.readAsStringSync());
  }

  /// The topics whose files hold uncommitted changes — a person's
  /// hand-edits.
  List<String> get handEdited {
    final root = _root;
    if (root == null) return const [];
    return [
      for (final path in ambientGit.worktreeDirtyPaths(root.path))
        if (path.endsWith('.md')) path.substring(0, path.length - '.md'.length),
    ];
  }

  /// One act: the body writes into the bank's own tree, and the line moves
  /// by an ordinary commit. The organ writes by moving the line.
  Future<Landing> land(
    String payload,
    void Function(Draft) body, {
    required Actor actor,
    String? say,
  }) async {
    final root = _root;
    if (root == null) {
      return Barred(
        'the bank has no line yet — instance "$mainInstanceId" of '
        '$name was never born',
      );
    }
    final gitDir = _gitDirOf(root.path);
    if (ambientGit.revParse(gitDir, 'refs/heads/$mainInstanceId') == null) {
      return Barred(
        'the bank has no line yet — instance "$mainInstanceId" of '
        '$name was never born',
      );
    }
    final following = ambientGit.currentBranch(root.path);
    if (following == null) {
      return Barred(
        'the worktree at ${root.path} follows no branch',
      );
    }
    final standing = ambientGit.revParse(gitDir, 'HEAD');
    if (standing == null) {
      return Barred(
        'the bank has no line yet — instance "$mainInstanceId" of '
        '$name was never born',
      );
    }
    final carried = ambientGit.worktreeDirtyPaths(root.path);
    if (carried.isNotEmpty) throw TreeCarriesWork(root.path, carried);
    try {
      body(Draft._(root));
    } catch (cause) {
      final discarded = ambientGit.worktreeDirtyPaths(root.path);
      ambientGit.worktreeDiscard(root.path, to: standing);
      throw ActUnwound(cause, directory: root.path, discarded: discarded);
    }
    final outcome = ambientGit.commitInWorktree(
      root.path,
      message: ent.Action.messageFor(payload, say: say),
      actor: actor,
    );
    final landed = outcome.commit;
    if (landed != null) {
      return Landed(ent.Action(
        gitDir: gitDir,
        ref: 'refs/heads/$following',
        commit: landed,
      ));
    }
    final discarded = ambientGit.worktreeDirtyPaths(root.path);
    ambientGit.worktreeDiscard(root.path, to: standing);
    return Barred(
      ent.gateRefusalIn(outcome.report) ?? 'refused by a gate',
    );
  }

  /// Brings the working tree to the landed line, or says why it could not.
  ///
  /// **Three outcomes, and none of them is silence.** A bank with no tree of
  /// ours standing at the uniform address is [NoTree] and never [Advanced].
  Advance advance() {
    final address = _address;
    if (!hasTree) return NoTree(address);
    final gitDir = _gitDirOf(address.path);
    final tip = ambientGit.revParse(gitDir, 'refs/heads/$mainInstanceId');
    if (tip == null) return NoTree(address);
    final carried = ambientGit.worktreeDirtyPaths(address.path);
    if (carried.isNotEmpty) {
      return Behind(
        blocking: carried,
        report: 'the tree at ${address.path} carries uncommitted work, '
            'and catching it up would overwrite it:\n  '
            '${carried.join('\n  ')}\n  '
            'commit it or set it aside first: git -C ${address.path} status',
      );
    }
    final branch = ambientGit.currentBranch(address.path);
    if (branch == mainInstanceId) return Advanced();
    final result = ambientGit.worktreeCheckout(address.path, to: tip);
    if (result.moved) return Advanced();
    return Behind(
      blocking: ambientGit.worktreeDirtyPaths(address.path),
      report: result.report,
    );
  }

  static String _gitDirOf(String workTree) {
    final asDir = Directory(p.join(workTree, '.git'));
    if (asDir.existsSync()) return asDir.path;
    final asFile = File(p.join(workTree, '.git'));
    if (asFile.existsSync()) {
      for (final line in asFile.readAsStringSync().split('\n')) {
        if (line.startsWith('gitdir:')) {
          final loc = line.substring('gitdir:'.length).trim();
          return p.isAbsolute(loc) ? loc : p.normalize(p.join(workTree, loc));
        }
      }
    }
    throw StateError('no git directory at $workTree');
  }

  static Iterable<File> _markdownFiles(Directory root) sync* {
    if (!root.existsSync()) return;
    for (final entry in root.listSync(recursive: true, followLinks: false)) {
      if (entry is! File || !entry.path.endsWith('.md')) continue;
      final rel = p.split(p.relative(entry.path, from: root.path));
      if (rel.contains('.git')) continue;
      yield entry;
    }
  }

  static String _topicOf(Directory root, File file) {
    final rel = p.relative(file.path, from: root.path);
    final withoutExtension = rel.substring(0, rel.length - '.md'.length);
    // A topic is a `/`-separated identifier — the form every wikilink in a
    // page's own body uses, and the form a `mem://bank/topic` address uses.
    // `p.relative` answers in the host's own separator, `\` on Windows, and
    // a topic catalogued that way matches no link a page ever spells: every
    // cross-reference in every page these tools write is forward-slash, by
    // convention no Windows checkout gets to opt out of.
    return p.split(withoutExtension).join('/');
  }
}

/// Resolution answers with a value: a bank that is not there is an ordinary
/// outcome, and the vantage it was not found from is the whole of what was
/// observed — never that it is absent from the machine.
sealed class Resolution {
  const Resolution();
}

final class Found extends Resolution {
  const Found(this.bank);
  final Bank bank;
}

final class NotFound extends Resolution {
  const NotFound(this.tried, this.vantage);

  /// Every name the lookup actually asked for, in the order it asked — a
  /// report naming only the bare form sends the reader hunting for a thing
  /// the tool never looked for.
  final List<String> tried;

  final String vantage;
}

/// The area an act writes in. It holds no policy: what a legal write is
/// belongs to the writer that calls it.
final class Draft {
  Draft._(this._directory);
  final Directory _directory;

  void write(Page page) {
    final file = File(p.join(_directory.path, '${page.topic}.md'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(page.serialize());
  }

  void remove(String topic) {
    final file = File(p.join(_directory.path, '$topic.md'));
    if (file.existsSync()) file.deleteSync();
  }
}

sealed class Landing {
  const Landing();
}

final class Landed extends Landing {
  const Landed(this.action);
  final ent.Action action;
}

/// A gate refused. Retrying is an infinite loop wearing a retry policy.
final class Barred extends Landing {
  const Barred(this.reason);
  final String reason;
}

sealed class Advance {
  const Advance();
}

final class Advanced extends Advance {
  const Advanced();
}

/// The tree could not be moved. Never discarded, never stashed, never
/// committed.
final class Behind extends Advance {
  const Behind({required this.blocking, this.report});

  /// What stands in the way, by path — the person's own uncommitted work in
  /// the ordinary case.
  final List<String> blocking;

  /// The substrate's or the primitive's own account of the decline, where the
  /// paths alone do not explain it.
  final String? report;
}

/// No tree of this bank stands at the uniform address, so a landed write is
/// nowhere anybody can read it.
final class NoTree extends Advance {
  const NoTree(this.address);

  /// Where a tree would stand if one did — the gitlink's own path under the
  /// super-repo, never composed by the caller.
  final Directory address;
}

/// The tree carries uncommitted work, and an act commits the whole of it.
final class TreeCarriesWork implements Exception {
  const TreeCarriesWork(this.directory, this.paths);

  final String directory;
  final List<String> paths;

  @override
  String toString() => [
        'the tree at $directory carries uncommitted work, '
            'and an act commits the whole of it',
        ...paths.map((path) => '  $path'),
        'commit it or set it aside first: git -C $directory status',
      ].join('\n');
}

/// The body threw; the tree was restored. Same obligation [Instance.act] had.
final class ActUnwound implements Exception {
  const ActUnwound(this.cause, {required this.directory, required this.discarded});

  final Object cause;
  final String directory;
  final List<String> discarded;

  @override
  String toString() => 'act unwound at $directory: $cause';
}
