// A real device with a scripted mind: the one thing in the walk that has to be
// faked. Everything else the fixture crosses — the portal, the ioctls, the
// protobuf on the wire, the subsystem base — is the shipped floor.
//
// It answers what it is shown, never a recorded sequence, so it is
// order-independent and survives the same session being run twice. Credentials
// are never consulted, which is what makes the walk reproducible anywhere.

import 'package:chat_inference/chat_inference.dart';

/// The provider's per-session state — the fixture has none, and says so.
final class FixtureSession {
  const FixtureSession();
}

const String fixtureVendor = 'fixture';

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

/// The model name is the scenario. `weather` is the loop's own fixture: asked a
/// question it thinks and calls, given a result it answers. `two-cities` calls
/// twice in one turn, which is what makes the executor's debt a matter of
/// coverage. Anything else just answers.
Stream<ChatEvent> _script(String model, List<ChatMessage> messages) {
  return switch (model) {
    'weather' => _lastIsPlainUser(messages) ? _thinkingThenCall() : _finalText(),
    'two-cities' => _lastIsPlainUser(messages) ? _twoCalls() : _finalText(),
    _ => _finalText(),
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

Stream<ChatEvent> _finalText() async* {
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
