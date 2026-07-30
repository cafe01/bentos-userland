/// The boot layer is PURE ROUTING (`llm` spec §1): it maps a `/dev/llm/*` path
/// to which driver to instantiate and serve — nothing more. It reads no
/// credentials. These assertions pin that: known vendors wire normally, and the
/// only boot-side failures are routing errors (malformed path, unknown vendor).
/// The missing-credential → EACCES path is the DRIVER's, covered in the driver
/// packages' tests.
library;

import 'package:bentos_userland/boot.dart';
import 'package:test/test.dart';

import 'package:bentos_userland/bundled_drivers.dart';

void main() {
  // The bundled vendors are wired from example/ (a dev/distribution concern),
  // never from the published lib. Registering them here proves the agnostic
  // routing table + the bundled wiring together.
  setUp(() {
    clearLlmDrivers();
    registerBundledLlmDrivers();
  });

  test('routes both shipped vendors by the path, never by app choice', () {
    expect(() => bootLlmDevice('/dev/llm/openai/gpt-4o-mini'), returnsNormally);
    expect(
      () => bootLlmDevice('/dev/llm/anthropic/claude-haiku-4-5'),
      returnsNormally,
    );
  });

  test('malformed device path is a routing error', () {
    expect(
      () => bootLlmDevice('/nope/openai/x'),
      throwsA(isA<LlmBootException>()),
    );
  });

  test('unknown vendor is a routing error', () {
    expect(
      () => bootLlmDevice('/dev/llm/cohere/command'),
      throwsA(isA<LlmBootException>()),
    );
  });
}
