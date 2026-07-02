import 'package:file/file.dart';

import 'residence.dart';

/// The outcome of a [PlaceInit.run]: whether a new place was created and the
/// line to report it.
final class PlaceInitResult {
  const PlaceInitResult({required this.created, required this.message});

  final bool created;
  final String message;
}

/// `place init`: promote a folder to a place by creating `.place/` and writing
/// `.place/place.yaml` from the given fields. Name defaults to the directory
/// name. A pre-existing place is reported cleanly, never clobbered.
final class PlaceInit {
  const PlaceInit(this.fs);

  final FileSystem fs;

  PlaceInitResult run(
    String dirPath, {
    String? name,
    String? owner,
    String? desc,
  }) {
    final root = fs.directory(fs.path.normalize(fs.path.absolute(dirPath)));
    final marker = Residence.markerDir(root, fs);
    final label = fs.path.basename(root.path);

    if (marker.existsSync()) {
      return PlaceInitResult(
        created: false,
        message: 'place already initialized  $label  →  ${marker.path}',
      );
    }

    marker.createSync(recursive: true);
    final resolvedName = name ?? label;
    Residence.metaFile(root, fs).writeAsStringSync(
      _yaml(resolvedName, owner, desc),
    );

    final ownerNote = owner == null ? '' : '  (owner: $owner)';
    return PlaceInitResult(
      created: true,
      message: 'initialized place  $label$ownerNote  →  ${marker.path}',
    );
  }

  String _yaml(String name, String? owner, String? desc) {
    final buf = StringBuffer()..writeln('name: $name');
    if (owner != null) buf.writeln('owner: $owner');
    if (desc != null) buf.writeln('description: $desc');
    return buf.toString();
  }
}
