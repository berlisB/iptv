import 'package:flutter/foundation.dart';
import 'package:iptv/core/storage/app_storage.dart';
import 'package:iptv/features/vod/data/tmdb_service.dart';
import 'package:iptv/features/vod/data/stream_service.dart';
import 'package:iptv/features/vod/data/anime_service.dart';
import 'package:iptv/features/vod/domain/media_entity.dart';
import 'package:iptv/features/vod/domain/anime_entity.dart';

enum VodCategory {
  trending, popular, movies, tv, anime, action, comedy, drama, horror
}

class VodProvider extends ChangeNotifier {
  List<MediaEntity> _trendingMovies = [];
  List<MediaEntity> _trendingTv = [];
  List<MediaEntity> _popularMovies = [];
  List<MediaEntity> _popularTv = [];
  List<MediaEntity> _filteredResults = [];
  List<MediaEntity> _searchResults = [];
  List<AnimeEntity> _animeResults = [];

  bool _isLoading = false;
  bool _isSearching = false;
  bool _isLoadingMore = false;
  String _searchQuery = '';
  VodCategory _selectedCategory = VodCategory.trending;

  // Pagination
  int _popularPage = 1;
  bool _hasMorePopular = true;
  int _genrePage = 1;
  bool _hasMoreGenre = true;
  String? _activeGenreName;

  // Anime state
  List<AnimeEntity> _animeSearchResults = [];
  List<AnimeEpisode> _animeEpisodes = [];
  AnimeEntity? _selectedAnime;
  bool _isAnimeLoading = false;
  List<String> _animeLangs = [];
  String _selectedAnimeLang = 'vostfr';

  // TV series state
  List<TvSeason> _tvSeasons = [];
  List<TvEpisode> _tvEpisodes = [];
  int _selectedTvSeason = 1;
  bool _isTvLoading = false;

  List<MediaEntity> get trendingMovies => _trendingMovies;
  List<MediaEntity> get trendingTv => _trendingTv;
  List<MediaEntity> get popularMovies => _popularMovies;
  List<MediaEntity> get popularTv => _popularTv;
  List<MediaEntity> get filteredResults => _filteredResults;
  List<MediaEntity> get searchResults => _searchResults;
  List<AnimeEntity> get animeResults => _animeResults;
  List<AnimeEntity> get animeSearchResults => _animeSearchResults;
  List<AnimeEpisode> get animeEpisodes => _animeEpisodes;
  set animeEpisodes(List<AnimeEpisode> v) => _animeEpisodes = v;
  AnimeEntity? get selectedAnime => _selectedAnime;
  set selectedAnime(AnimeEntity? v) => _selectedAnime = v;
  bool get isLoading => _isLoading;
  bool get isSearching => _isSearching;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _activeGenreName != null ? _hasMoreGenre : _hasMorePopular;
  bool get isAnimeLoading => _isAnimeLoading;
  String get searchQuery => _searchQuery;
  VodCategory get selectedCategory => _selectedCategory;

  // TV series getters
  List<TvSeason> get tvSeasons => _tvSeasons;
  List<TvEpisode> get tvEpisodes => _tvEpisodes;
  int get selectedTvSeason => _selectedTvSeason;
  bool get isTvLoading => _isTvLoading;

  // Anime lang getters
  List<String> get animeLangs => _animeLangs;
  String get selectedAnimeLang => _selectedAnimeLang;

  Future<void> loadAll() async {
    if (_isLoading) return;
    _isLoading = true;
    _popularPage = 1;
    _hasMorePopular = true;
    notifyListeners();

    try {
      final results = await Future.wait([
        TmdbService.fetchTrendingMovies(),
        TmdbService.fetchTrendingTv(),
        TmdbService.fetchPopularMovies(page: 1),
        TmdbService.fetchPopularTv(page: 1),
      ]);

      _trendingMovies = results[0];
      _trendingTv = results[1];
      _popularMovies = results[2];
      _popularTv = results[3];

      _applyCategory();
    } catch (e) {
      debugPrint('[VOD] loadAll error: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Charge la page suivante de contenu populaire / par genre.
  Future<void> loadMore() async {
    if (_isLoadingMore || !hasMore) return;
    if (_selectedCategory == VodCategory.anime) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      if (_activeGenreName != null) {
        // Pagination par genre
        _genrePage++;
        final genreResults = await _fetchGenrePage(_activeGenreName!, _genrePage);
        if (genreResults.isEmpty) {
          _hasMoreGenre = false;
        } else {
          _filteredResults = [..._filteredResults, ...genreResults];
          _filteredResults
              .sort((a, b) => b.voteAverage.compareTo(a.voteAverage));
        }
      } else {
        // Pagination populaire
        _popularPage++;
        final movieResults =
            await TmdbService.fetchPopularMovies(page: _popularPage);
        final tvResults =
            await TmdbService.fetchPopularTv(page: _popularPage);

        if (movieResults.isEmpty && tvResults.isEmpty) {
          _hasMorePopular = false;
        } else {
          _popularMovies = [..._popularMovies, ...movieResults];
          _popularTv = [..._popularTv, ...tvResults];
          _applyCategory();
        }
      }
    } catch (e) {
      debugPrint('[VOD] loadMore error: $e');
    }

    _isLoadingMore = false;
    notifyListeners();
  }

  void setCategory(VodCategory category) {
    _selectedCategory = category;
    _activeGenreName = null;
    _genrePage = 1;
    _hasMoreGenre = true;

    if (category == VodCategory.anime) {
      _filteredResults = [];
    } else {
      _applyCategory();
    }
    notifyListeners();
  }

  /// Recherche unifiée: TMDB + animes-sama en parallèle.
  Future<void> search(String query) async {
    _searchQuery = query;
    if (query.trim().isEmpty) {
      _searchResults = [];
      _animeSearchResults = [];
      _isSearching = false;
      notifyListeners();
      return;
    }

    _isSearching = true;
    notifyListeners();

    final tmdbResults = await TmdbService.search(query);
    final animeResults = await AnimeService.search(query);

    _searchResults = tmdbResults;
    _animeSearchResults = animeResults;
    _isSearching = false;
    notifyListeners();
  }

  Future<StreamResult?> getStream(MediaEntity media,
      {int season = 1, int episode = 1}) async {
    if (media.isMovie) {
      return StreamService.getMovieStream(media.tmdbId);
    }
    return StreamService.getTvStream(media.tmdbId,
        season: season, episode: episode);
  }

  // --- Anime ---

  Future<void> loadAnimeEpisodes(AnimeEntity anime, {String? lang}) async {
    _selectedAnime = anime;
    _selectedAnimeLang = lang ?? _selectedAnimeLang;
    _isAnimeLoading = true;
    _animeEpisodes = [];
    notifyListeners();
    try {
      final seasons = await AnimeService.getSeasons(anime.slug);
      if (seasons.isEmpty) {
        _animeEpisodes = await AnimeService.getEpisodes(
            anime.slug, lang: _selectedAnimeLang);
      } else {
        final langs = seasons.map((s) => s['lang']!).toSet().toList();
        _animeLangs = langs;

        if (!langs.contains(_selectedAnimeLang) && langs.isNotEmpty) {
          _selectedAnimeLang = langs.first;
        }

        final targetSeason = seasons.firstWhere(
          (s) => s['lang'] == _selectedAnimeLang,
          orElse: () => seasons.first,
        );
        _animeEpisodes = await AnimeService.getEpisodes(
          anime.slug,
          season: targetSeason['season']!,
          lang: _selectedAnimeLang,
        );
      }
    } catch (e) {
      debugPrint('[VOD] loadAnimeEpisodes error: $e');
    }
    _isAnimeLoading = false;
    notifyListeners();
  }

  void setAnimeLang(String lang) {
    if (_selectedAnime == null || lang == _selectedAnimeLang) return;
    _selectedAnimeLang = lang;
    loadAnimeEpisodes(_selectedAnime!, lang: lang);
  }

  void clearAnimeSelection() {
    _selectedAnime = null;
    _animeEpisodes = [];
    _animeLangs = [];
    _selectedAnimeLang = 'vostfr';
    notifyListeners();
  }

  // --- TV Series ---

  Future<void> loadTvSeasons(MediaEntity media) async {
    if (!media.isTv) return;
    _isTvLoading = true;
    _tvEpisodes = [];
    _selectedTvSeason = 1;
    notifyListeners();
    try {
      _tvSeasons = await TmdbService.fetchTvSeasons(media.tmdbId);
      if (_tvSeasons.isNotEmpty) {
        // Reprendre à la dernière saison regardée si dispo.
        final progress = AppStorage.getWatchProgress(media.tmdbId);
        if (progress != null) {
          final savedSeason = progress['season']!;
          final exists =
              _tvSeasons.any((s) => s.seasonNumber == savedSeason);
          _selectedTvSeason = exists ? savedSeason : _tvSeasons.first.seasonNumber;
        } else {
          _selectedTvSeason = _tvSeasons.first.seasonNumber;
        }
        await loadTvEpisodes(media, season: _selectedTvSeason);
      }
    } catch (e) {
      debugPrint('[VOD] loadTvSeasons error: $e');
    }
    _isTvLoading = false;
    notifyListeners();
  }

  Future<void> loadTvEpisodes(MediaEntity media, {required int season}) async {
    _selectedTvSeason = season;
    _tvEpisodes = [];
    notifyListeners();
    try {
      _tvEpisodes = await TmdbService.fetchTvEpisodes(
        media.tmdbId,
        season: season,
      );
    } catch (e) {
      debugPrint('[VOD] loadTvEpisodes error: $e');
    }
    notifyListeners();
  }

  void clearTvState() {
    _tvSeasons = [];
    _tvEpisodes = [];
    _selectedTvSeason = 1;
    _isTvLoading = false;
  }

  Future<String?> getAnimeStream(AnimeEpisode episode) async {
    if (episode.hasDirectHls) return episode.directHlsUrl;
    return AnimeService.extractStreamUrl(episode.embedUrl, episode.provider);
  }

  // --- Watch history helpers (exposées pour l'UI) ---

  bool isEpisodeWatched(int tmdbId, int season, int episode) {
    return AppStorage.getWatchedEpisodes(tmdbId, season: season)
        .contains(episode);
  }

  int countWatchedInSeason(int tmdbId, int season) {
    return AppStorage.countWatchedInSeason(tmdbId, season);
  }

  // --- Genre pagination ---

  Future<List<MediaEntity>> _fetchGenrePage(String genre, int page) async {
    final genreId = _genreNameToId(genre);
    if (genreId == null) return [];
    return TmdbService.fetchByGenre(genreId, page: page);
  }

  static int? _genreNameToId(String name) {
    const map = {
      'Action': 28,
      'Comédie': 35,
      'Drame': 18,
      'Horreur': 27,
    };
    return map[name];
  }

  void _applyCategory() {
    switch (_selectedCategory) {
      case VodCategory.trending:
        _filteredResults = [..._trendingMovies, ..._trendingTv];
        break;
      case VodCategory.popular:
        _filteredResults = [..._popularMovies, ..._popularTv];
        break;
      case VodCategory.movies:
        _filteredResults = [..._trendingMovies, ..._popularMovies];
        break;
      case VodCategory.tv:
        _filteredResults = [..._trendingTv, ..._popularTv];
        break;
      case VodCategory.anime:
        _filteredResults = [];
        break;
      case VodCategory.action:
        _applyGenreFilter('Action');
        break;
      case VodCategory.comedy:
        _applyGenreFilter('Comédie');
        break;
      case VodCategory.drama:
        _applyGenreFilter('Drame');
        break;
      case VodCategory.horror:
        _applyGenreFilter('Horreur');
        break;
    }
    _filteredResults.sort((a, b) => b.voteAverage.compareTo(a.voteAverage));
  }

  void _applyGenreFilter(String genre) {
    // Filtrer depuis les résultats déjà chargés + cache local.
    final all = [
      ..._trendingMovies, ..._trendingTv,
      ..._popularMovies, ..._popularTv,
    ];
    final fromCache = all.where((m) => m.genres.contains(genre)).toList();
    if (fromCache.isNotEmpty) {
      _filteredResults = fromCache;
      _activeGenreName = genre;
      _genrePage = 1;
      _hasMoreGenre = true;
    } else {
      // Première fois : fetch depuis TMDb.
      _activeGenreName = genre;
      _genrePage = 1;
      _hasMoreGenre = true;
      TmdbService.fetchByGenre(_genreNameToId(genre) ?? 28).then((results) {
        if (_selectedCategory.name == genre.toLowerCase() ||
            _activeGenreName == genre) {
          _filteredResults = results;
          _filteredResults
              .sort((a, b) => b.voteAverage.compareTo(a.voteAverage));
          notifyListeners();
        }
      });
    }
  }
}
