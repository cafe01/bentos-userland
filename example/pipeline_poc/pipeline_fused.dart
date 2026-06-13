// Step 2: sort stage replaced by fake SortProcess (implements Process).
// The wiring is identical to pipeline_real.dart — only the constructor changes.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// In-isolate fake that sorts its stdin lines and writes them to stdout.
/// Implements Process so the wiring does not change.
class SortProcess implements Process {
  @override
  final IOSink stdin;
  @override
  final Stream<List<int>> stdout;
  @override
  final Stream<List<int>> stderr = const Stream.empty();
  @override
  final Future<int> exitCode;
  @override
  int get pid => -1;

  SortProcess._(this.stdin, this.stdout, this.exitCode);

  factory SortProcess(List<String> args) {
    final inController  = StreamController<List<int>>();
    final outController = StreamController<List<int>>();
    final exitCompleter = Completer<int>();

    final sink = IOSink(inController.sink);

    Future<void> run() async {
      final lines = await inController.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .toList();
      lines.sort();
      for (final line in lines) {
        outController.add(utf8.encode('$line\n'));
      }
      await outController.close();
      exitCompleter.complete(0);
    }

    run();

    return SortProcess._(sink, outController.stream, exitCompleter.future);
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => false;
}

Future<void> main() async {
  final dataFile = '${Directory.current.path}/example/pipeline_poc/data.txt';

  final cat   = await Process.start('cat', [dataFile]);
  final sort1 = SortProcess([]);            // ← fake, constructor only
  final uniq  = await Process.start('uniq', ['-c']);
  final sort2 = await Process.start('sort', ['-rn']);

  // Wiring unchanged from pipeline_real.dart.
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
