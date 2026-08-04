// manifest.dart — the reader of bentos-release.json.
//
// The manifest is the registry: what this repo produces, declared once, read by
// install.sh to know what to compile and by CI to know what to publish. This
// tool is the only parser, so the two can never disagree about the file.
//
// Dart rather than jq: install.sh already requires the Dart SDK to compile
// anything at all, so parsing here costs no new dependency on any machine that
// could have run the script in the first place.
//
// **The version has one home, and it is the pubspec.** The committed manifest
// declares INTENT — product, executables, platforms; the published one carries
// FACTS — the sha256 of each artifact, stamped when the binary exists. The
// version is a fact of that same kind, so `enrich` stamps it from the pubspec
// beside the artifacts. A `version` field committed into bentos-release.json
// would be the same truth declared twice, which is how the v0.1.2 tag published
// a release announcing 0.1.1.
//
// What does NOT collapse is tag versus pubspec: git's name and the package's
// name, neither derivable from the other. That seam is gated instead.
//
//   dart tool/manifest.dart names
//   dart tool/manifest.dart entrypoint <name>
//   dart tool/manifest.dart plan <platform>        # name<TAB>entrypoint, one per line
//   dart tool/manifest.dart version
//   dart tool/manifest.dart enrich <platform> <dir> <out>  # artifacts from binaries
//   dart tool/manifest.dart check-tag <tag>                 # pre-flight, blocks
//   dart tool/manifest.dart check-published <tag> <fetched-manifest> <release-title>

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:yaml/yaml.dart';

const manifestPath = 'bentos-release.json';
const pubspecPath = 'pubspec.yaml';

/// The one home. Read from the package's own pubspec, never from the manifest.
String pubspecVersion() {
  final file = File(pubspecPath);
  if (!file.existsSync()) {
    stderr.writeln('error: $pubspecPath not found (run from the package root)');
    exit(1);
  }
  final version = (loadYaml(file.readAsStringSync()) as Map)['version'];
  if (version is! String || version.isEmpty) {
    stderr.writeln('error: $pubspecPath declares no version');
    exit(1);
  }
  return version;
}

/// A tag names a version by convention: `v0.1.2` is `0.1.2`.
String versionOfTag(String tag) => tag.startsWith('v') ? tag.substring(1) : tag;

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart tool/manifest.dart '
        '<names|entrypoint|plan|version|enrich> [args]');
    exit(64);
  }

  final file = File(manifestPath);
  if (!file.existsSync()) {
    stderr.writeln('error: $manifestPath not found (run from the package root)');
    exit(1);
  }
  final doc = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final executables = (doc['executables'] as List).cast<Map<String, dynamic>>();

  switch (args.first) {
    case 'version':
      stdout.writeln(pubspecVersion());

    // Pre-flight, and it blocks: the tag being cut against the version of the
    // commit it points at. Nothing downstream can catch this one, because the
    // tag is the only fact the build never reads.
    case 'check-tag':
      if (args.length < 2) usage('check-tag <tag>');
      final tag = args[1];
      final declared = pubspecVersion();
      if (versionOfTag(tag) != declared) {
        stderr.writeln(
            'error: tag $tag would publish $pubspecPath version $declared');
        exit(1);
      }
      stdout.writeln('$tag matches $pubspecPath version $declared');

    // The witness over what the world actually received: the manifest FETCHED
    // back from the release and the release's own title, against the tag. It
    // reads neither the pubspec nor the manifest this run produced — a gate
    // testifying about the variable the value came from agrees, and agrees
    // wrongly.
    case 'check-published':
      if (args.length < 4) {
        usage('check-published <tag> <fetched-manifest> <release-title>');
      }
      final tag = args[1];
      final expected = versionOfTag(tag);
      final fetched =
          jsonDecode(File(args[2]).readAsStringSync()) as Map<String, dynamic>;
      final title = args[3];
      var bad = false;
      final published = fetched['version'];
      if (published != expected) {
        stderr.writeln('error: release $tag publishes a manifest declaring '
            '${published ?? "no version"}');
        bad = true;
      }
      if (!title.contains(expected)) {
        stderr.writeln('error: release $tag is titled "$title"');
        bad = true;
      }
      if (bad) exit(1);
      stdout.writeln('$tag: published manifest and title both say $expected');

    case 'names':
      for (final e in executables) {
        stdout.writeln(e['name']);
      }

    case 'entrypoint':
      if (args.length < 2) usage('entrypoint <name>');
      final name = args[1];
      final match = executables.where((e) => e['name'] == name);
      if (match.isEmpty) {
        stderr.writeln('error: no such executable: $name');
        exit(1);
      }
      stdout.writeln(match.first['entrypoint']);

    case 'plan':
      if (args.length < 2) usage('plan <platform>');
      final platform = args[1];
      for (final e in executables) {
        final platforms = (e['platforms'] as List).cast<String>();
        if (platforms.contains(platform)) {
          stdout.writeln('${e['name']}\t${e['entrypoint']}');
        }
      }

    // The names declared for a platform that the enriched manifest has no
    // artifact for — the gate over a build, and the one reading that says a
    // declared executable silently failed to compile.
    case 'missing':
      if (args.length < 3) usage('missing <platform> <enriched-manifest>');
      final platform = args[1];
      final built = ((jsonDecode(File(args[2]).readAsStringSync())
              as Map<String, dynamic>)['artifacts'] as List)
          .cast<Map<String, dynamic>>()
          .where((a) => a['platform'] == platform)
          .map((a) => a['name'])
          .toSet();
      for (final e in executables) {
        final platforms = (e['platforms'] as List).cast<String>();
        if (platforms.contains(platform) && !built.contains(e['name'])) {
          stdout.writeln(e['name']);
        }
      }

    case 'enrich':
      if (args.length < 4) usage('enrich <platform> <dir> <out>');
      enrich(doc, executables, args[1], args[2], File(args[3]));

    default:
      stderr.writeln('error: unknown verb: ${args.first}');
      exit(64);
  }
}

Never usage(String form) {
  stderr.writeln('usage: dart tool/manifest.dart $form');
  exit(64);
}

/// Records one artifact per compiled binary found in [dir], for [platform],
/// writing the enriched document to [out].
///
/// CI's half of the manifest: an artifact is a claim that a binary exists and
/// hashes to this, so nothing is recorded for an executable that did not build.
/// The source manifest is never touched — the enriched form is a release asset,
/// and [out] may be a previous pass's output, so a matrix accumulates: artifacts
/// for other platforms are preserved and this platform's are replaced.
///
/// The version is stamped here, from the pubspec, for the same reason the
/// sha256 are: both are facts about what was built.
void enrich(
  Map<String, dynamic> doc,
  List<Map<String, dynamic>> executables,
  String platform,
  String dir,
  File out,
) {
  // Rebuilt rather than assigned, so the stamped version reads where it always
  // read — second, above the executables it describes.
  doc = {
    'product': doc['product'],
    'version': pubspecVersion(),
    'executables': doc['executables'],
    'artifacts': doc['artifacts'] ?? [],
  };
  if (out.existsSync()) {
    doc['artifacts'] =
        (jsonDecode(out.readAsStringSync()) as Map<String, dynamic>)['artifacts'];
  }
  final kept = ((doc['artifacts'] as List?) ?? [])
      .cast<Map<String, dynamic>>()
      .where((a) => a['platform'] != platform)
      .toList();

  for (final e in executables) {
    final name = e['name'] as String;
    final platforms = (e['platforms'] as List).cast<String>();
    if (!platforms.contains(platform)) continue;

    final binary = File('$dir/$name');
    if (!binary.existsSync()) {
      stderr.writeln('  skipped $name — not built for $platform');
      continue;
    }
    final bytes = binary.readAsBytesSync();
    kept.add({
      'name': name,
      'platform': platform,
      'asset': '$name-$platform',
      'sha256': sha256.convert(bytes).toString(),
      'size': bytes.length,
    });
  }

  kept.sort((a, b) {
    final byName = (a['name'] as String).compareTo(b['name'] as String);
    return byName != 0
        ? byName
        : (a['platform'] as String).compareTo(b['platform'] as String);
  });
  doc['artifacts'] = kept;
  out.writeAsStringSync('${JsonEncoder.withIndent('  ').convert(doc)}\n');
  stdout.writeln('enriched ${out.path}: ${kept.length} artifact(s)');
}
