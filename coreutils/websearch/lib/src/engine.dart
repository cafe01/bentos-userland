/// Supported search engine backends.
enum Engine {
  ddgr('ddgr'),
  googler('googler');

  const Engine(this.binary);

  /// The CLI binary name for this engine.
  final String binary;

  static Engine parse(String name) {
    return switch (name) {
      'ddgr' => Engine.ddgr,
      'googler' => Engine.googler,
      _ => throw ArgumentError('Unknown engine: "$name". Supported: ddgr.'),
    };
  }
}
