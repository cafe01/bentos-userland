# bentos_userland

The bentos stdlib — what userland app programmers depend on. The client-side syscall surface over bentos-kernel capabilities, layered like libc.

## For the app programmer

You consume capabilities as devices, through file operations. The transport — real `/dev` node, gRPC, in-process — is a linking detail you never see.

### Core layer (`package:bentos_userland/bentos_userland.dart`)

The raw surface, when you need it:

```dart
final bentos = /* a portal — see below */;

final fd = await bentos.open('/dev/llm/anthropic/claude-haiku-4-5');
await bentos.write(fd, frame);        // one call, one frame
final out = await bentos.read(fd);    // next frame; empty = EOF
await bentos.close(fd);
```

- **The fd is the session** — `open()` allocates it, all device state hangs off it, `close()` ends it.
- **Payloads are opaque bytes** at this layer; typed frames belong to subsystem headers.
- Errors are `BentosException` with a POSIX-style errno (`enoent`, `ebadf`, ...).

### Subsystem headers (`package:bentos_userland/chat.dart`)

Each device class gets a typed layer on top — the `sys/chat.h` pattern. For `/dev/llm/*`:

```dart
import 'package:bentos_userland/chat.dart';

final device = BentosChatDevice(bentos, '/dev/llm/anthropic/claude-haiku-4-5');

await for (final event in device.infer([ChatMessage.userText('Hello!')])) {
  if (event case TextDelta(:final text)) stdout.write(text);
}
```

`infer()` is sugar over the surface: one `write()` per message, the first `read()` triggers inference, each `ChatEvent` is one `read()` on the fd, the stream ends at `Complete`. Types and codec come from `package:chat_inference`.

### Portals

A portal is an implementation of `Bentos` — which door your program enters the kernel through:

| Portal | Status |
|---|---|
| `InProcessBentos` | shipped — kernel, driver, and consumer in one process (dev/test) |
| gRPC | planned — any host, remote-capable |
| real POSIX `/dev` (CUSE) | planned — Linux, any Unix program |

```dart
// In-process: connect a Driver SDK driver to a channel pair and map its path.
final pair = StreamChannelController<Uint8List>();
driver.serveChannel(pair.foreign);
final bentos = InProcessBentos(capMap: {'/dev/llm/anthropic/': pair.local});
```

## Example

[`example/llm.dart`](example/llm.dart) — `llm <prompt>`, a streaming chat consumer. Waiting on the first chat driver to be wired into its marked slot.

## Authority

- Architecture — `hq/workshop/bentos/bentos-kernel-architecture.md` (§2 surface, §3 portals, §5 stdlib layering)
- Chat subsystem spec — `hq/workshop/bentos/chatinference-subsystem.md`
