import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:iptv/features/vod/domain/media_entity.dart';

/// Service pour récupérer les métadonnées films/séries depuis TMDb.
/// API gratuite pour usage non-commercial.
class TmdbService {
  TmdbService._();

  static const String _baseUrl = 'https://api.themoviedb.org/3';

  // Token TMDb v4 (lecture seule, usage non-commercial). Injectable à la
  // compilation : flutter build … --dart-define=TMDB_API_KEY=<token>
  // Créer le sien sur https://www.themoviedb.org/settings/api
  static const String _apiToken = String.fromEnvironment(
    'TMDB_API_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiJlNzZhM2JhNDEwMTk1YjZiODliMDFkNzE1ZjBkNmVlOCIsIm5iZiI6MTc4MTU0ODM4My4wMTksInN1YiI6IjZhMzA0NTVmNWU5NDM4NzhlMzY1NTEzMSIsInNjb3BlcyI6WyJhcGlfcmVhZCJdLCJ2ZXJzaW9uIjoxfQ.0pxuGhDNUlgocxUPhvMoaOzJXWmkyWTMotAJTw8So7M',
  );

  static const _headers = {
    'Authorization': 'Bearer $_apiToken',
    'Content-Type': 'application/json;charset=utf-8',
  };

  /// Recherche de films populaires (paginable).
  static Future<List<MediaEntity>> fetchPopularMovies({int page = 1}) async {
    try {
      final resp = await http
          .get(
            Uri.parse('$_baseUrl/movie/popular?language=fr-FR&page=$page'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      final results = data['results'] as List? ?? [];
      return results
          .map((j) => _parseMovie(j))
          .where((m) => m != null)
          .cast<MediaEntity>()
          .toList();
    } catch (e) {
      debugPrint('[TMDb] fetchPopularMovies error: $e');
      return [];
    }
  }

  /// Recherche de séries populaires
  static Future<List<MediaEntity>> fetchPopularTv({int page = 1}) async {
    try {
      final resp = await http
          .get(
            Uri.parse('$_baseUrl/tv/popular?language=fr-FR&page=$page'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      final results = data['results'] as List? ?? [];
      return results
          .map((j) => _parseTv(j))
          .where((m) => m != null)
          .cast<MediaEntity>()
          .toList();
    } catch (e) {
      debugPrint('[TMDb] fetchPopularTv error: $e');
      return [];
    }
  }

  /// Films tendance (trending) — pas de pagination TMDb sur trending/week.
  static Future<List<MediaEntity>> fetchTrendingMovies() async {
    try {
      final resp = await http
          .get(
            Uri.parse('$_baseUrl/trending/movie/week?language=fr-FR'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      final results = data['results'] as List? ?? [];
      return results
          .map((j) => _parseMovie(j))
          .where((m) => m != null)
          .cast<MediaEntity>()
          .toList();
    } catch (e) {
      debugPrint('[TMDb] fetchTrendingMovies error: $e');
      return [];
    }
  }

  /// Séries tendance
  static Future<List<MediaEntity>> fetchTrendingTv() async {
    try {
      final resp = await http
          .get(
            Uri.parse('$_baseUrl/trending/tv/week?language=fr-FR'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      final results = data['results'] as List? ?? [];
      return results
          .map((j) => _parseTv(j))
          .where((m) => m != null)
          .cast<MediaEntity>()
          .toList();
    } catch (e) {
      debugPrint('[TMDb] fetchTrendingTv error: $e');
      return [];
    }
  }

  /// Recherche libre
  static Future<List<MediaEntity>> search(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final resp = await http
          .get(
            Uri.parse(
                '$_baseUrl/search/multi?language=fr-FR&query=${Uri.encodeComponent(query)}'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      final results = data['results'] as List? ?? [];
      return results
          .where((j) => j['media_type'] == 'movie' || j['media_type'] == 'tv')
          .map((j) {
            if (j['media_type'] == 'movie') return _parseMovie(j);
            return _parseTv(j);
          })
          .where((m) => m != null)
          .cast<MediaEntity>()
          .toList();
    } catch (e) {
      debugPrint('[TMDb] search error: $e');
      return [];
    }
  }

  /// Films par catégorie (action, comédie, etc.)
  static Future<List<MediaEntity>> fetchByGenre(int genreId,
      {bool isTv = false, int page = 1}) async {
    final type = isTv ? 'tv' : 'movie';
    try {
      final resp = await http
          .get(
            Uri.parse(
                '$_baseUrl/discover/$type?language=fr-FR&with_genres=$genreId&sort_by=popularity.desc&page=$page'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      final results = data['results'] as List? ?? [];
      return results
          .map((j) => isTv ? _parseTv(j) : _parseMovie(j))
          .where((m) => m != null)
          .cast<MediaEntity>()
          .toList();
    } catch (e) {
      debugPrint('[TMDb] fetchByGenre error: $e');
      return [];
    }
  }

  static MediaEntity? _parseMovie(Map<String, dynamic> j) {
    try {
      final title = j['title'] as String? ?? '';
      if (title.isEmpty) return null;
      final genres = (j['genre_ids'] as List?)
              ?.map((id) => _genreName(id as int))
              .toList() ??
          [];
      return MediaEntity(
        tmdbId: j['id'] as int,
        title: title,
        overview: j['overview'] as String? ?? '',
        posterPath: j['poster_path'] as String? ?? '',
        backdropPath: j['backdrop_path'] as String? ?? '',
        voteAverage: (j['vote_average'] as num?)?.toDouble() ?? 0,
        releaseDate: j['release_date'] as String? ?? '',
        mediaType: MediaType.movie,
        genres: genres,
      );
    } catch (_) {
      return null;
    }
  }

  static MediaEntity? _parseTv(Map<String, dynamic> j) {
    try {
      final name = j['name'] as String? ?? '';
      if (name.isEmpty) return null;
      final genres = (j['genre_ids'] as List?)
              ?.map((id) => _genreName(id as int))
              .toList() ??
          [];
      return MediaEntity(
        tmdbId: j['id'] as int,
        title: name,
        overview: j['overview'] as String? ?? '',
        posterPath: j['poster_path'] as String? ?? '',
        backdropPath: j['backdrop_path'] as String? ?? '',
        voteAverage: (j['vote_average'] as num?)?.toDouble() ?? 0,
        releaseDate: j['first_air_date'] as String? ?? '',
        mediaType: MediaType.tv,
        genres: genres,
        seasonCount: j['number_of_seasons'] as int?,
        episodeCount: j['number_of_episodes'] as int?,
      );
    } catch (_) {
      return null;
    }
  }

  /// Récupère la liste des saisons d'une série.
  static Future<List<TvSeason>> fetchTvSeasons(int tmdbId) async {
    try {
      final resp = await http
          .get(
            Uri.parse('$_baseUrl/tv/$tmdbId?language=fr-FR'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      final seasons = data['seasons'] as List? ?? [];
      return seasons
          .where((s) => (s['season_number'] as int? ?? 0) > 0)
          .map((s) => TvSeason(
                seasonNumber: s['season_number'] as int? ?? 0,
                episodeCount: s['episode_count'] as int? ?? 0,
                name: s['name'] as String? ?? '',
              ))
          .toList();
    } catch (e) {
      debugPrint('[TMDb] fetchTvSeasons error: $e');
      return [];
    }
  }

  /// Récupère les épisodes d'une saison donnée.
  static Future<List<TvEpisode>> fetchTvEpisodes(int tmdbId,
      {int season = 1}) async {
    try {
      final resp = await http
          .get(
            Uri.parse(
                '$_baseUrl/tv/$tmdbId/season/$season?language=fr-FR'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      final episodes = data['episodes'] as List? ?? [];
      return episodes
          .map((e) => TvEpisode(
                seasonNumber: season,
                episodeNumber: e['episode_number'] as int? ?? 0,
                name: e['name'] as String? ?? '',
                overview: e['overview'] as String? ?? '',
                airDate: e['air_date'] as String? ?? '',
              ))
          .toList();
    } catch (e) {
      debugPrint('[TMDb] fetchTvEpisodes error: $e');
      return [];
    }
  }

  static String _genreName(int id) {
    const genres = {
      28: 'Action', 12: 'Aventure', 16: 'Animation', 35: 'Comédie',
      80: 'Crime', 99: 'Documentaire', 18: 'Drame', 10751: 'Famille',
      14: 'Fantastique', 36: 'Histoire', 27: 'Horreur', 10402: 'Musique',
      9648: 'Mystère', 10749: 'Romance', 878: 'Sci-Fi', 53: 'Thriller',
      10752: 'Guerre', 37: 'Western',
      // TV
      10759: 'Action & Aventure', 10762: 'Enfants', 10763: 'News',
      10764: 'Réalité', 10765: 'Sci-Fi & Fantasy', 10766: 'Soap',
      10767: 'Talk', 10768: 'Guerre & Politique',
    };
    return genres[id] ?? 'Autre';
  }
}
