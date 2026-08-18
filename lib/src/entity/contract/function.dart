/// `function` — the verbs a thing ships, run against an instance (R2.8.1).
library;

/// The slice of `Instance` this component owns.
abstract interface class InstanceFunctions {
  /// Run a function the manifest declares, against this instance.
  ///
  /// The instance's state is the ground the function runs on: it is
  /// materialized as a view first if it is not already standing, and the
  /// function is told where. Throws [FunctionNotDeclared] for a verb the
  /// manifest does not name — never a shell error a caller has to parse.
  Future<FunctionResult> run(String verb, {List<String> args = const []});
}

final class FunctionResult {
  const FunctionResult({
    required this.code,
    required this.out,
    required this.err,
  });
  final int code;
  final String out;
  final String err;
}

final class FunctionNotDeclared implements Exception {
  const FunctionNotDeclared(this.entity, this.verb);
  final String entity;
  final String verb;
}
