import 'package:file/memory.dart';
import 'package:mem/src/mem/mem_runner.dart';
import 'package:mem/src/mem/model/mem_node.dart';
import 'package:path/path.dart' as p;

const kPlace = '/test-place';
const kAgent = 'tester';

typedef RunResult = ({int exitCode, String out, String err});

MemoryFileSystem seedFs({
  Map<MemPageType, Map<String, double>> pages = const {},
  Map<String, String> content = const {},
  String agent = kAgent,
  String place = kPlace,
}) {
  final fs = MemoryFileSystem();
  final agentDir = p.join(place, '.mem', agent);
  fs.directory(agentDir).createSync(recursive: true);

  final buf = StringBuffer()
    ..writeln('agent: $agent')
    ..writeln('scope: test')
    ..writeln('edges:');
  for (final type in MemPageType.values) {
    final typePages = pages[type] ?? {};
    buf.write('  ${type.name}:');
    if (typePages.isEmpty) {
      buf.writeln(' []');
    } else {
      buf.writeln();
      for (final e in typePages.entries) {
        buf.writeln('    - ${e.key}.md: ${e.value}');
      }
    }
  }

  fs.file(p.join(agentDir, 'mem.yml')).writeAsStringSync(buf.toString());

  for (final e in content.entries) {
    fs.file(p.join(agentDir, '${e.key}.md')).writeAsStringSync(e.value);
  }

  return fs;
}

Future<RunResult> runMem(
  List<String> args, {
  MemoryFileSystem? fs,
  String? stdinContent,
}) async {
  final outBuf = StringBuffer();
  final errBuf = StringBuffer();
  final runner = MemRunner(out: outBuf, err: errBuf, fileSystem: fs, stdinContent: stdinContent);
  await runner.run(args);
  return (
    exitCode: runner.exitCode,
    out: outBuf.toString(),
    err: errBuf.toString(),
  );
}
