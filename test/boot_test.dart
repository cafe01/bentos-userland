/// The boot layer is the inertness seam (`llm` spec §1): it owns vendor routing,
/// credential reading and driver construction so a coreutil's `main` never does.
/// These assertions pin that contract without touching the network — a wired
/// device opens cleanly; every config error surfaces as [LlmBootException].
library;

import 'package:bentos_userland/bentos_userland.dart';
import 'package:bentos_userland/boot.dart';
import 'package:test/test.dart';

void main() {
  const env = {'OPENAI_API_KEY': 'fake', 'ANTHROPIC_API_KEY': 'fake'};

  test('wires a known vendor and the device opens against the served driver',
      () async {
    final bentos =
        bootLlmDevice('/dev/llm/openai/gpt-4o-mini', environment: env);
    final fd = await bentos.open('/dev/llm/openai/gpt-4o-mini',
        mode: OpenMode.readOnly);
    expect(fd, greaterThan(0));
    await bentos.close(fd);
  });

  test('routes both shipped vendors by the path, never by app choice', () {
    expect(
      () => bootLlmDevice('/dev/llm/anthropic/claude-haiku-4-5',
          environment: env),
      returnsNormally,
    );
  });

  test('malformed device path is a boot error', () {
    expect(
      () => bootLlmDevice('/nope/openai/x', environment: env),
      throwsA(isA<LlmBootException>()),
    );
  });

  test('unknown vendor is a boot error', () {
    expect(
      () => bootLlmDevice('/dev/llm/cohere/command', environment: env),
      throwsA(isA<LlmBootException>()),
    );
  });

  test('missing credential is a boot error, raised behind the device', () {
    expect(
      () => bootLlmDevice('/dev/llm/openai/gpt-4o-mini', environment: const {}),
      throwsA(isA<LlmBootException>()),
    );
  });
}
