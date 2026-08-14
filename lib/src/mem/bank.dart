import 'dart:io';

import 'package:path/path.dart' as p;

import '../entity/action.dart' as ent;
import '../entity/entity.dart';
import '../git/git_ambient.dart';
import '../git/model/actor.dart';
import '../git/model/commit.dart';
import 'page.dart';

/// The store, and the only component of `mem/` that speaks to it. Resolves a
/// name from a vantage, reads the tree in place, lands writes as acts, and
/// brings the tree to the landed line.
///
/// **No path is composed here or anywhere else** — [resolve] hands the name
/// and the vantage to [Entity] and takes what comes back. Reads are in place
/// (`pages()`, `page()`); writes are never in place (`land()`), and
/// reconciling the tree afterwards is `advance()` and nothing else.
final class Bank {
  Bank._(this._entity, this.vantage);

  final Entity _entity;

  /// The vantage this bank was resolved from, carried so that a walk opening
  /// a foreign bank opens it from the same one without being told.
  final String vantage;

  /// The instance a bank is: house convention, ratified — a bank has exactly
  /// one line, and it is this one.
  static const String mainInstanceId = 'main';

  /// The suffix a bank's entity name carries: the ontology's, not the being's.
  /// `$BENTOS_AGENT` names the being — `alfred` — while the entity installed
  /// beside it is `alfred.mem`, which is why [resolve] may not take the name
  /// it is given as the last word.
  static const String suffix = '.mem';

  /// Resolves a bank through the entity primitive, walking up from [vantage].
  /// The only place a bank name becomes a thing on disk.
  ///
  /// **Exactly as given first, then with [suffix] appended.** A being's
  /// ambient bank is named by `$BENTOS_AGENT`, which holds the being's name
  /// and never the entity's, so a lookup that took the name verbatim and
  /// stopped left every default unreachable and made `-b alfred.mem` the only
  /// working form. Exact-first keeps an entity literally named `x.mem` — or
  /// any entity whose name is its own whole truth — winning its own name
  /// before the fallback is ever tried.
  ///
  /// Forces the walk by reading the entity's genesis — not, as the design
  /// once said, its manifest: a bank authored by [Entity.create] carries no
  /// manifest at all (`create` leaves genesis empty), so reading one would
  /// throw on every bank of our own making rather than only on the absent
  /// ones. Genesis forces the identical walk and exists on every entity that
  /// [EntityNotInstalled] does not already rule out.
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

  /// One lookup, or null where no such entity is installed from [vantage].
  static Bank? _open(String name, {required String vantage}) {
    final entity = Entity(name, from: vantage);
    try {
      entity.genesis;
    } on EntityNotInstalled {
      return null;
    }
    return Bank._(entity, vantage);
  }

  String get name => _entity.name;

  /// Every page of the bank, read from the working tree with ordinary file
  /// IO. **Not `Instance.read`**, which answers at the ref with no worktree
  /// and would make a hand-edited page invisible.
  ///
  /// A bank with no working tree materialized has no pages, and says so with
  /// an empty list.
  List<Page> pages() {
    final root = _entity.materializedAt;
    if (root == null) return const [];
    return [
      for (final file in _markdownFiles(root))
        Page.parse(_topicOf(root, file), file.readAsStringSync()),
    ];
  }

  Page? page(String topic) {
    final root = _entity.materializedAt;
    if (root == null) return null;
    final file = File(p.join(root.path, '$topic.md'));
    if (!file.existsSync()) return null;
    return Page.parse(topic, file.readAsStringSync());
  }

  /// The topics whose files hold uncommitted changes — a person's
  /// hand-edits. No entity member answers this; it is Git's own status,
  /// asked here because this is the one component allowed to ask.
  List<String> get handEdited {
    final root = _entity.materializedAt;
    if (root == null) return const [];
    return [
      for (final path in ambientGit.worktreeDirtyPaths(root.path))
        if (path.endsWith('.md')) path.substring(0, path.length - '.md'.length),
    ];
  }

  /// One act: the body writes into a private area the primitive opens, and
  /// the line moves by compare-and-swap. Nothing is written in the working
  /// tree.
  ///
  /// The floor's four outcomes are collapsed to three: [ent.Diverged] is a
  /// fetch outcome, structurally unreachable from `Instance.act`'s commit
  /// path, and a case that cannot fire must not be handed to callers.
  Future<Landing> land(
    String payload,
    void Function(Draft) body, {
    required Actor actor,
    String? say,
  }) async {
    final result = await _entity.instance(mainInstanceId).act(
      payload,
      (workspace) => body(Draft._(workspace.directory)),
      actor: actor,
      say: say,
    );
    return switch (result) {
      ent.Landed(:final action) => Landed(action),
      ent.Contested(:final expected, :final found) =>
        Contested(expected: expected, found: found),
      ent.Barred(:final reason) => Barred(reason),
      ent.Diverged() => throw StateError(
          'unreachable: Instance.act cannot diverge — divergence is a fetch '
          'outcome, and land never fetches'),
    };
  }

  /// Brings the working tree to the landed line, or leaves it untouched.
  ///
  /// A bank whose tree was never materialized has nothing to advance —
  /// bringing one up for the first time is out of this stage's scope, and
  /// deferred exactly as the design defers it.
  Advance advance() {
    final at = _entity.materializedAt;
    if (at == null) return Advanced();
    final result =
        _entity.instance(mainInstanceId).materialization(at.path).refresh();
    if (result.moved) return Advanced();
    return Behind(blocking: ambientGit.worktreeDirtyPaths(at.path));
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
    return rel.substring(0, rel.length - '.md'.length);
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

/// The floor's own outcomes, passed through unflattened bar [ent.Diverged],
/// which never fires here. Each one is a different obligation on the
/// caller — proceed, retry, stop — and collapsing any two would produce a
/// false account of what happened.
sealed class Landing {
  const Landing();
}

final class Landed extends Landing {
  const Landed(this.action);
  final ent.Action action;
}

/// The line moved underneath the act. Nobody decided anything, and retrying
/// is correct and terminates.
final class Contested extends Landing {
  const Contested({this.expected, this.found});
  final Commit? expected;
  final Commit? found;
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

/// The tree could not be moved because the person has work in it. Never
/// discarded, never stashed, never committed.
final class Behind extends Advance {
  const Behind({required this.blocking});
  final List<String> blocking;
}
