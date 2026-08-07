/// Where cosmetics stop: what a keystroke resolved to mean for the floor,
/// never for the screen. A slash at the head of a line, a keybinding, a menu
/// all become one of these two and nothing below learns which.
library;

sealed class Intent {
  const Intent();
}

/// Speak the composing buffer, as it stands at the moment this is acted on.
final class Speak extends Intent {
  const Speak();
}

/// A command, named explicitly rather than typed as prose.
final class InvokeCommand extends Intent {
  const InvokeCommand(this.verb, this.args);

  final String verb;
  final List<String> args;
}
