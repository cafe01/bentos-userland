/// `/dev/llm/fixture/<scenario>` — a real device with a scripted mind.
///
/// It is the inference subsystem's loopback: everything around it is the shipped
/// floor — the portal, the ioctls, the protobuf on the wire, the subsystem base
/// — and the only thing faked is the model. Credentials are never consulted,
/// which is what makes it the device a walk of the whole loop can be driven on,
/// anywhere, by anyone, for free.
///
/// It answers what it is shown rather than a recorded sequence, so it is
/// order-independent and a session may be run against it twice.
library;

import 'package:chat_inference/chat_inference.dart';

/// The provider's per-session state — the fixture has none, and says so.
final class FixtureSession {
  const FixtureSession();
}

const String fixtureVendor = 'fixture';

/// The scenarios the fixture answers to, `<model>` being the scenario's name:
///
/// - `weather` — asked a question it thinks and calls `get_weather`; given the
///   result, it answers. The loop's own fixture.
/// - `two-cities` — two calls in one turn, which is what makes the executor's
///   debt a matter of coverage rather than of message count.
/// - anything else — `echo`: it answers with the text it was last told.
ChatInferenceDriver<FixtureSession> fixtureChatDriver({required String model}) {
  return ChatInferenceDriver<FixtureSession>(
    ChatProviderOps<FixtureSession>(
      capabilities: () => ChatCapabilities(
        model: model,
        provider: fixtureVendor,
        maxContextTokens: 200000,
        maxOutputTokens: 8192,
        reasoningSupport: ReasoningSupport.budget,
        supportsFunctions: true,
        supportedMimeTypes: const ['image/png'],
        supportsStreaming: true,
        supportedInputFormats: const ['unstructured', 'structured'],
        supportedOutputFormats: const ['unstructured', 'structured'],
        supportedStopReasons: const [
          'endTurn',
          'maxTokens',
          'stopSequence',
          'functionCall',
        ],
      ),
      openSession: () => const FixtureSession(),
      process: (messages, config, {required providerSession}) =>
          _script(model, messages),
      providerError: (e) =>
          ChatError(kind: ChatErrorKind.unknown, message: e.toString()),
      dispose: ({required providerSession}) {},
    ),
  );
}

Stream<ChatEvent> _script(String model, List<ChatMessage> messages) {
  return switch (model) {
    'weather' => _lastIsPlainUser(messages) ? _thinkingThenCall() : _weatherAnswer(),
    'two-cities' => _lastIsPlainUser(messages) ? _twoCalls() : _weatherAnswer(),
    _ => _echo(messages),
  };
}

bool _lastIsPlainUser(List<ChatMessage> messages) {
  final last = messages.last;
  return last.role == ChatRole.user &&
      last.content.whereType<FunctionResultContent>().isEmpty;
}

Stream<ChatEvent> _thinkingThenCall() async* {
  yield const ThinkingStart(0);
  yield const ThinkingDelta(index: 0, text: 'Recife fica no litoral; ');
  yield const ThinkingDelta(index: 0, text: 'vou consultar.');
  yield const ThinkingStop(0);
  yield const FunctionCallStart(index: 1, id: 'call_1', name: 'get_weather');
  yield const FunctionArgsDelta(index: 1, partialJson: '{"city":');
  yield const FunctionArgsDelta(index: 1, partialJson: '"Recife"}');
  yield const FunctionCallStop(1);
  yield const Complete(ChatMetadata(
    model: 'fixture/weather',
    stopReason: FunctionCall(),
    usage: TokenUsage(inputTokens: 412, outputTokens: 96, reasoningTokens: 64),
  ));
}

Stream<ChatEvent> _twoCalls() async* {
  yield const FunctionCallStart(index: 0, id: 'a', name: 'get_weather');
  yield const FunctionArgsDelta(index: 0, partialJson: '{"city":"Recife"}');
  yield const FunctionCallStop(0);
  yield const FunctionCallStart(index: 1, id: 'b', name: 'get_weather');
  yield const FunctionArgsDelta(index: 1, partialJson: '{"city":"Olinda"}');
  yield const FunctionCallStop(1);
  yield const Complete(ChatMetadata(
    model: 'fixture/two-cities',
    stopReason: FunctionCall(),
  ));
}

Stream<ChatEvent> _weatherAnswer() async* {
  yield const TextStart(0);
  yield const TextDelta(index: 0, text: '29°C e ');
  yield const TextDelta(index: 0, text: 'céu limpo.');
  yield const TextStop(0);
  yield const Complete(ChatMetadata(
    model: 'fixture/weather',
    stopReason: EndTurn(),
    usage: TokenUsage(inputTokens: 528, outputTokens: 12),
  ));
}

/// The neutral scenario: the last thing said back, so a face can be exercised
/// without a script to remember.
Stream<ChatEvent> _echo(List<ChatMessage> messages) async* {
  final said = messages.reversed
      .where((m) => m.role == ChatRole.user)
      .expand((m) => m.content.whereType<TextContent>())
      .map((t) => t.text)
      .firstOrNull;
  yield const TextStart(0);
  yield TextDelta(index: 0, text: said == null ? '(nothing was said)' : 'echo: $said');
  yield const TextStop(0);
  yield const Complete(ChatMetadata(
    model: 'fixture/echo',
    stopReason: EndTurn(),
    usage: TokenUsage(inputTokens: 1, outputTokens: 1),
  ));
}
