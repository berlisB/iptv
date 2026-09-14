/// Parité d'identité entre le pipeline Python et l'app.
///
/// `lib/core/utils/stable_id.dart` et `tools/healthcheck.py` calculent le MÊME
/// identifiant de chaîne. Tout écart casse silencieusement la correspondance
/// favoris / récents / EPG entre catalog.json et l'app — un bug invisible en
/// CI et pénible à diagnostiquer sur l'appareil.
///
/// Les valeurs attendues ci-dessous sont les sorties réelles des fonctions
/// Python, relevées avec :
///
///   cd tools && python3 -c "import healthcheck as h; \
///       print(h.channel_id(h.strip_feed_suffix('00sReplay.us@SD'), 'x'))"
///
/// Si un de ces tests casse, corrigez le côté qui a dérivé — ne mettez pas la
/// valeur attendue à jour sans avoir rejoué le Python.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv/core/utils/stable_id.dart';

void main() {
  group('stripFeedSuffix', () {
    // L'index iptv-org publie une entrée par variante de qualité : les deux
    // doivent retomber sur une seule identité, sinon la chaîne apparaît en
    // double dans le catalogue au lieu d'avoir deux URLs.
    test('retire le suffixe de flux @SD/@HD', () {
      expect(stripFeedSuffix('00sReplay.us@SD'), '00sReplay.us');
      expect(stripFeedSuffix('00sReplay.us@HD'), '00sReplay.us');
      expect(stripFeedSuffix('CCTV1.cn@SD'), 'CCTV1.cn');
    });

    test('préserve la casse, exigée par EpgIdMapping', () {
      expect(stripFeedSuffix('France24English.fr'), 'France24English.fr');
      expect(stripFeedSuffix('Africa24.fr'), 'Africa24.fr');
    });

    test('laisse intact un tvg-id sans suffixe', () {
      expect(stripFeedSuffix('Buzzr.us'), 'Buzzr.us');
      expect(stripFeedSuffix('NoAt'), 'NoAt');
      expect(stripFeedSuffix(''), '');
    });

    test('coupe au premier @ et trime', () {
      expect(stripFeedSuffix('a@b@c'), 'a');
      expect(stripFeedSuffix('  Spaced.fr@HD  '), 'Spaced.fr');
    });
  });

  group('stableChannelId — parité avec channel_id() Python', () {
    test('tvg-id présent → minuscules, suffixe retiré', () {
      const cases = {
        '00sReplay.us@SD': '00sreplay.us',
        '00sReplay.us@HD': '00sreplay.us',
        'France24English.fr': 'france24english.fr',
        'Africa24.fr': 'africa24.fr',
        'Buzzr.us': 'buzzr.us',
        'a@b@c': 'a',
        '  Spaced.fr@HD  ': 'spaced.fr',
        'NoAt': 'noat',
        'CCTV1.cn@SD': 'cctv1.cn',
      };
      cases.forEach((tvgId, expected) {
        expect(stableChannelId(tvgId: tvgId, name: 'Fallback Name'), expected,
            reason: 'tvgId=$tvgId');
      });
    });

    test('tvg-id absent → hash FNV-1a du nom normalisé', () {
      expect(stableChannelId(tvgId: '', name: 'Fallback Name'),
          'n-aec4e67bbdd7c95a');
    });
  });

  group('normalizeName — parité avec normalize_name() Python', () {
    test('retire les tokens de qualité et la ponctuation', () {
      expect(normalizeName('Fallback Name'), 'fallback name');
      expect(normalizeName('Sky Sports HD'), 'sky sports');
      expect(normalizeName('Canal+ 4K'), 'canal');
    });

    test('traite les accents comme de la ponctuation, comme Python', () {
      // Le pipeline n'utilise pas \b justement parce que Python et Dart
      // divergent sur les accents ; le découpage sur [^a-z0-9]+ donne donc
      // 'a d coiffe' des deux côtés. Ce test verrouille cette bizarrerie.
      expect(normalizeName('Ça Décoiffe FHD'), 'a d coiffe');
    });
  });

  group('fnv1a64Hex — parité avec fnv1a64_hex() Python', () {
    test('reproduit les hashes Python sur 16 caractères hex', () {
      expect(fnv1a64Hex('fallback name'), 'aec4e67bbdd7c95a');
      expect(fnv1a64Hex('sky sports'), '660a0c8c5651923d');
      expect(fnv1a64Hex('canal'), '024f593aa748ad40');
      expect(fnv1a64Hex('a d coiffe'), 'd3627353da9a4024');
    });
  });
}
