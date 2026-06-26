import 'package:file/file.dart';

import 'body_source.dart';
import 'model/mem_node.dart';
import 'model/mem_resolver.dart';
import 'model/mem_writer.dart';
import 'page_selector.dart';
import 'render/recall_render.dart';
import 'render/survey_render.dart';
import 'word_count.dart';

/// Shared execution context threaded into each subcommand.
final class MemContext {
  MemContext({
    required this.resolver,
    required this.place,
    required this.out,
    required this.err,
    required this.fileSystem,
    String? stdinContent,
  })  : bodySource = BodySource(fileSystem, stdinOverride: stdinContent),
        writer = MemWriter(fileSystem),
        surveyRender = const SurveyRender(),
        recallRender = const RecallRender(),
        pageSelector = const PageSelector();

  final MemResolver resolver;
  final String place;
  final StringSink out;
  final StringSink err;
  final FileSystem fileSystem;
  final BodySource bodySource;
  final MemWriter writer;
  final SurveyRender surveyRender;
  final RecallRender recallRender;
  final PageSelector pageSelector;
  final WordCount wordCount = const WordCount();

  MemNode? get node => resolver.resolve(place);
}
