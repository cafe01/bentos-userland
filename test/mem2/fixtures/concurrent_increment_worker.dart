import 'dart:io';

import 'package:bentos_userland/src/mem2/model/attention.dart';
import 'package:bentos_userland/src/mem2/model/mem_page.dart';
import 'package:bentos_userland/src/mem2/model/mem_writer.dart';

/// A worker process for the cross-process write-serialization witness. Each
/// invocation is one `mem`-shaped writer racing real siblings on one real
/// page: [increments] times, it derives the page's body as one more than
/// whatever it currently holds. This is a read-modify-write, not a constant
/// write — a lost update between two processes is only visible when each
/// successor is derived from what was actually read, under the guard that
/// is supposed to make that read-then-write indivisible.
///
/// Args: <page path> <increments>
void main(List<String> args) {
  final file = File(args[0]);
  final increments = int.parse(args[1]);
  final writer = MemWriter(() => DateTime.utc(2026, 1, 1));

  for (var i = 0; i < increments; i++) {
    writer.mutateBody(
      file,
      'counter',
      type: MemType.semantic,
      attention: Attention.parse('0.5'),
      transform: (current) => '${(current.isEmpty ? 0 : int.parse(current.trim())) + 1}',
    );
  }
}
