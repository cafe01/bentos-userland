import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../../entity/entity.dart';
import '../../entity/manifest.dart';
import '../../git/model/commit.dart';
import '../habitat_index.dart';
import '../place.dart';
import '../place_runner.dart';

/// `place materialize [-r] [<path>]` — bring the constellation down.
///
/// **The one verb of the coreutil that is two owners' work joined.** Enumerating
/// what is installed and descending the tree of places is the landlord's, and it
/// is why `Place.materialize` does not exist as a member; checking a repository
/// out at the commit the place holds it at is the tenant's, because the entity
/// owns its own layout under the plot absolutely. The join happens here, exactly
/// as `install` joins the same two halves from the other side.
///
/// **What comes down is decided by cardinality**, which the manifest declares
/// and which defaults to plural — undeclared, we do not know, and genesis is
/// what we know the thing is.
final class MaterializeCommand extends Command<void> {
  MaterializeCommand(this._runner) {
    argParser.addFlag(
      'recursive',
      abbr: 'r',
      negatable: false,
      help: 'Descend into the places nested under this one.',
    );
  }

  final PlaceRunner _runner;

  @override
  String get name => 'materialize';

  @override
  String get description =>
      'Bring the constellation down: check out what is installed here at the commit this place holds it at.';

  @override
  String get invocation => 'place materialize [-r] [<path>]';

  @override
  Future<void> run() async {
    final place = _runner.placeAt(
        argResults!.rest.isEmpty ? null : argResults!.rest.first);
    final recursive = argResults!.flag('recursive');

    final places = recursive
        ? _descend(_runner.indexUnder(place).root)
        : <Place>[place];

    for (final at in places) {
      for (final record in at.installed) {
        _bring(at, record);
      }
    }
  }

  /// The subtree of places, this one first — the landlord's half, and the
  /// existing scan is the whole of it.
  List<Place> _descend(PlaceNode node) => [
        node.place,
        for (final child in node.children) ..._descend(child),
      ];

  void _bring(
    Place place,
    ({String name, String url, String path, String sha}) record,
  ) {
    final path = p.join(place.root.path, record.path);
    final entity = Entity(record.name, from: place.root.path);

    final Commit at;
    try {
      at = _commitFor(entity, record.sha);
    } on Object catch (error) {
      // Not installed here, or an entity with no genesis at all: a record the
      // place declares and cannot bring down. One line per failure and the run
      // continues — a constellation is brought down as far as it goes.
      _runner.err.writeln('place: cannot materialize ${record.name}: $error');
      _runner.exitCode = 1;
      return;
    }

    entity.materialize(at, path: path);
    _runner.out.writeln('${record.name}\t$path\t${at.sha}');
  }

  /// Which commit this place's declaration means.
  ///
  /// Singular: the pin, because a singular entity's pin *is* its state. Plural:
  /// genesis, because no single sha could mean *all the objects*, and taking the
  /// pin at face value there would present one instance as the class. Absent
  /// manifest — the ordinary condition of a freshly authored entity, whose
  /// genesis is empty — reads as plural, which is the conservative half.
  Commit _commitFor(Entity entity, String pinned) {
    final genesis = entity.genesis;
    Cardinality cardinality;
    try {
      cardinality = entity.manifest.cardinality;
    } on Object {
      cardinality = Cardinality.plural;
    }
    if (cardinality == Cardinality.plural || pinned.isEmpty) return genesis;
    return Commit(pinned);
  }
}
