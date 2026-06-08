/// Default-command aliasing: bare `llm "prompt…"` routes to the `prompt`
/// command, while `llm chat` / `llm models` / `llm --help` route to themselves.
///
/// Mirrors `agent_runner`'s `_withDefaultSubcommand`, but at the top level: the
/// default is the prompt command, not a subcommand of a parent.
library;

/// Returns [args] with [defaultCommand] prepended when the invocation names no
/// known command — i.e. when the first non-flag token is a prompt, not a
/// command name.
///
/// When there is no non-flag token (only top-level flags, or an empty
/// invocation), the result depends on [stdinHasPrompt]: with a piped stdin
/// supplying the prompt (`echo … | llm`), it still routes to [defaultCommand]
/// so the command reads stdin; without it, args are left untouched so the
/// runner can handle `--version` / `--help` / show usage.
///
/// The first non-flag token, when present and one of [knownCommands], is left
/// untouched (an explicit `llm chat` / `llm models`).
List<String> withDefaultCommand(
  List<String> args,
  Set<String> knownCommands, {
  String defaultCommand = 'prompt',
  bool stdinHasPrompt = false,
}) {
  final firstNonFlag = args.firstWhere(
    (a) => !a.startsWith('-'),
    orElse: () => '',
  );
  if (firstNonFlag.isEmpty) {
    return stdinHasPrompt ? [defaultCommand, ...args] : args;
  }
  if (knownCommands.contains(firstNonFlag)) return args;
  return [defaultCommand, ...args];
}
