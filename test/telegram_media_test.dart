/// Le parseur de noms de release décide de la qualité perçue de toute la
/// section Telegram : sans titre et année propres, pas de match TMDB, donc pas
/// d'affiche ni de synopsis. Ces cas sont des noms de fichiers réels.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv/features/telegram/domain/telegram_media.dart';

TelegramMedia parse(String name) =>
    parseTelegramFileName(name, messageId: 1, fileId: 2);

void main() {
  group('films', () {
    test('release classique séparée par des points', () {
      final m = parse('The.Matrix.1999.1080p.BluRay.x264-GROUP.mkv');
      expect(m.title, 'The Matrix');
      expect(m.year, 1999);
      expect(m.kind, TelegramMediaKind.movie);
      expect(m.quality, '1080p');
    });

    test('année entre parenthèses et espaces', () {
      final m = parse('Inception (2010) TRUEFRENCH 2160p.mp4');
      expect(m.title, 'Inception');
      expect(m.year, 2010);
      expect(m.quality, '2160p');
      expect(m.languageTags, contains('VF'));
    });

    test('titre sans année', () {
      final m = parse('Le.Fabuleux.Destin.d.Amelie.Poulain.FRENCH.mkv');
      expect(m.title, "Le Fabuleux Destin d Amelie Poulain");
      expect(m.year, 0);
      expect(m.languageTags, contains('VF'));
    });

    test('un titre numérique n\'est pas confondu avec l\'année', () {
      // Piège classique : « 1917 » est le titre, « 2019 » l'année.
      final m = parse('1917.2019.MULTI.1080p.mkv');
      expect(m.title, '1917');
      expect(m.year, 2019);
      expect(m.languageTags, contains('MULTI'));
    });

    test('retient la meilleure qualité annoncée', () {
      final m = parse('Dune.2021.2160p.HDR.x265.mkv');
      expect(m.quality, '2160p');
      expect(m.year, 2021);
    });
  });

  group('séries', () {
    test('format SxxExx', () {
      final m = parse('Breaking.Bad.S01E05.MULTI.1080p.mkv');
      expect(m.title, 'Breaking Bad');
      expect(m.kind, TelegramMediaKind.episode);
      expect(m.season, 1);
      expect(m.episode, 5);
      expect(m.displayTitle, 'Breaking Bad · S01E05');
    });

    test('format compact NxNN', () {
      final m = parse('Friends.3x12.VOSTFR.720p.avi');
      expect(m.title, 'Friends');
      expect(m.season, 3);
      expect(m.episode, 12);
      expect(m.languageTags, contains('VOSTFR'));
    });

    test('format verbeux français', () {
      final m = parse('Kaamelott Saison 2 Episode 8 VF.mp4');
      expect(m.title, 'Kaamelott');
      expect(m.season, 2);
      expect(m.episode, 8);
    });

    test('numéros à trois chiffres', () {
      final m = parse('One.Piece.S01E1089.VOSTFR.1080p.mkv');
      expect(m.season, 1);
      expect(m.episode, 1089);
      expect(m.title, 'One Piece');
    });
  });

  group('robustesse', () {
    test('un nom sans métadonnée reste affichable', () {
      final m = parse('film sans rien.mp4');
      expect(m.title, 'film sans rien');
      expect(m.displayTitle, 'film sans rien');
    });

    test('un nom uniquement technique retombe sur le nom de fichier', () {
      final m = parse('1080p.x264.mkv');
      expect(m.displayTitle.isNotEmpty, true);
    });

    test('les crochets sont traités comme des séparateurs', () {
      final m = parse('[Team] Akira [1988] [1080p].mkv');
      expect(m.title, 'Team Akira');
      expect(m.year, 1988);
    });
  });

  group('affichage', () {
    test('taille lisible', () {
      expect(
        const TelegramMedia(
          messageId: 1, fileId: 1, fileName: 'x', title: 'x',
          sizeBytes: 4509715660,
        ).readableSize,
        '4.2 Go',
      );
      expect(
        const TelegramMedia(
          messageId: 1, fileId: 1, fileName: 'x', title: 'x',
          sizeBytes: 0,
        ).readableSize,
        '',
      );
    });

    test('durée lisible', () {
      expect(
        const TelegramMedia(
          messageId: 1, fileId: 1, fileName: 'x', title: 'x',
          durationSeconds: 8130,
        ).readableDuration,
        '2h15',
      );
      expect(
        const TelegramMedia(
          messageId: 1, fileId: 1, fileName: 'x', title: 'x',
          durationSeconds: 1500,
        ).readableDuration,
        '25min',
      );
    });

    test('un film affiche son année', () {
      const m = TelegramMedia(
        messageId: 1, fileId: 1, fileName: 'x', title: 'Alien', year: 1979,
      );
      expect(m.displayTitle, 'Alien (1979)');
    });
  });
}
