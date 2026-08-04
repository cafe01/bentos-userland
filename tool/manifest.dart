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
//   dart tool/manifest.dart names
//   dart tool/manifest.dart entrypoint <name>
//   dart tool/manifest.dart plan <platform>        # name<TAB>entrypoint, one per line
//   dart tool/manifest.dart version
//   dart tool/manifest.dart enrich <platform> <dir> <out>  # artifacts from binaries

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const manifestPath = 'bentos-release.json';

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
      stdout.writeln(doc['version']);

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
void enrich(
  Map<String, dynamic> doc,
  List<Map<String, dynamic>> executables,
  String platform,
  String dir,
  File out,
) {
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
