/// Le choix de la fiche TMDB détermine l'affiche et le synopsis affichés.
/// TMDB renvoie volontiers des suites et des homonymes : ces cas verrouillent
/// le fait qu'on préfère ne RIEN afficher plutôt qu'une mauvaise fiche.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv/features/telegram/domain/telegram_media.dart';
import 'package:iptv/features/telegram/provider/telegram_provider.dart';
import 'package:iptv/features/vod/domain/media_entity.dart';

MediaEntity movie(String title, String year, {int id = 1}) => MediaEntity(
      tmdbId: id,
      title: title,
      releaseDate: year,
      mediaType: MediaType.movie,
    );

MediaEntity tv(String title, String year, {int id = 1}) => MediaEntity(
      tmdbId: id,
      title: title,
      releaseDate: year,
      mediaType: MediaType.tv,
    );

TelegramMedia film(String title, int year) => TelegramMedia(
      messageId: 1, fileId: 1, fileName: 'x', title: title, year: year,
    );

TelegramMedia episode(String title) => TelegramMedia(
      messageId: 1, fileId: 1, fileName: 'x', title: title,
      kind: TelegramMediaKind.episode, season: 1, episode: 1,
    );

void main() {
  test('titre et année exacts gagnent', () {
    final best = TelegramProvider.bestMatch([
      movie('Dune: Part Two', '2024', id: 2),
      movie('Dune', '1984', id: 3),
      movie('Dune', '2021', id: 4),
    ], film('Dune', 2021));
    expect(best?.tmdbId, 4);
  });

  test('un épisode préfère une série à un film homonyme', () {
    final best = TelegramProvider.bestMatch([
      movie('Fargo', '1996', id: 10),
      tv('Fargo', '2014', id: 11),
    ], episode('Fargo'));
    expect(best?.tmdbId, 11);
  });

  test('un écart d\'un an reste accepté (sortie décalée)', () {
    final best = TelegramProvider.bestMatch(
      [movie('Parasite', '2019', id: 20)],
      film('Parasite', 2020),
    );
    expect(best?.tmdbId, 20);
  });

  test('une année trop éloignée disqualifie', () {
    final best = TelegramProvider.bestMatch(
      [movie('The Thing', '1982', id: 30)],
      film('The Thing', 2011),
    );
    expect(best, isNull);
  });

  test('un résultat sans rapport est rejeté plutôt que deviné', () {
    final best = TelegramProvider.bestMatch(
      [movie('Un tout autre film', '1999', id: 40)],
      film('Mon Film Introuvable', 2015),
    );
    expect(best, isNull);
  });

  test('liste vide ne casse pas', () {
    expect(TelegramProvider.bestMatch([], film('Rien', 2000)), isNull);
  });
}
