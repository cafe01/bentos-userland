import 'package:bentos_userland/src/manifest/particle.dart';
import 'package:test/test.dart';

/// CONTRACT — the vocabulary tables encode the Standard Model faithfully, and
/// lookup distinguishes editable / v2-deferred / unknown. These guard against the
/// realm and arity facts drifting from the doc.
void main() {
  group('lookupParticle — realm is a function of the particle (§V)', () {
    test('abstract prose particles resolve to the abstract realm', () {
      for (final name in ['essence', 'purpose', 'trait', 'capacity', 'principle']) {
        expect(lookupParticle(name)?.realm, Realm.abstract_, reason: name);
      }
    });

    test('concrete prose particles resolve to the concrete realm', () {
      for (final name in ['protocol', 'knowledge', 'pattern', 'antipattern']) {
        expect(lookupParticle(name)?.realm, Realm.concrete, reason: name);
      }
    });

    test('the capacity/protocol pair splits realms — same concept, two particles', () {
      expect(lookupParticle('capacity')!.realm, Realm.abstract_);
      expect(lookupParticle('protocol')!.realm, Realm.concrete);
    });
  });

  group('lookupParticle — arity', () {
    test('essence and purpose are singletons (no handle)', () {
      expect(lookupParticle('essence')!.arity, Arity.singleton);
      expect(lookupParticle('purpose')!.arity, Arity.singleton);
    });

    test('trait/principle/knowledge/pattern/antipattern/capacity/protocol are named', () {
      for (final name in [
        'trait', 'principle', 'knowledge', 'pattern', 'antipattern', 'capacity', 'protocol',
      ]) {
        expect(lookupParticle(name)!.arity, Arity.named, reason: name);
      }
    });
  });

  group('scope boundaries', () {
    test('relation particles are NOT editable in v1 but ARE recognised as deferred', () {
      expect(lookupParticle('requires'), isNull);
      expect(lookupParticle('attracts'), isNull);
      expect(v2RelationParticles, containsAll(['requires', 'attracts']));
    });

    test('assembly particles and nonsense are simply unknown', () {
      for (final name in ['molecule', 'organism', 'atom', 'data', 'frobnicate']) {
        expect(lookupParticle(name), isNull, reason: name);
        expect(v2RelationParticles, isNot(contains(name)), reason: name);
      }
    });

    test('v is an editable attribute, not a particle', () {
      expect(lookupParticle('v'), isNull);
      expect(editableAttrs, contains('v'));
    });
  });
}
