// Step 1: all-real-binaries pipeline
// Equivalent shell: cat data.txt | sort | uniq -c | sort -rn
import 'dart:io';

Future<void> main() async {
  final dataFile = '${Directory.current.path}/example/pipeline_poc/data.txt';

  final cat   = await Process.start('cat',  [dataFile]);
  final sort1 = await Process.start('sort', []);
  final uniq  = await Process.start('uniq', ['-c']);
  final sort2 = await Process.start('sort', ['-rn']);

  // Each addStream closes the downstream stdin when the upstream stdout ends.
  cat.stdout.pipe(sort1.stdin);
  sort1.stdout.pipe(uniq.stdin);
  uniq.stdout.pipe(sort2.stdin);
  await stdout.addStream(sort2.stdout);

  await Future.wait([
    cat.exitCode,
    sort1.exitCode,
    uniq.exitCode,
    sort2.exitCode,
  ]);
}
