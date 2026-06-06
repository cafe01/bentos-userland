# bentos_userland

The bentos stdlib — what userland app programmers depend on. The client-side syscall surface over bentos-kernel capabilities.

## What lives here

- **`Bentos`** — the syscall surface contract (`open/read/write/ioctl/poll/fsync/close`), the stdlib's core layer. The only layer that knows portals exist; payloads are opaque bytes. Implementations are portals.
- **`InProcessBentos`** — the in-process portal: a minimal kernel (static cap map, open-session table, the `close()` → `flush`+`release` vocabulary translation) connecting consumer and driver inside one Dart process. The dev/test door.
- **`InProcessDriver`** — the driver side of that portal, speaking the driver vocabulary (libfuse-shaped).

Subsystem-typed layers (e.g. chat-inference's `ChatDevice`) sit on top of `Bentos` in their own packages; the kernel never hears of them.

## Authority

- Architecture — `hq/workshop/bentos/bentos-kernel-architecture.md` (§2 surface, §3 portals, §5 stdlib layering)
- First subsystem — `hq/workshop/bentos/chatinference-subsystem.md`
