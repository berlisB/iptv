/// État de la section Telegram : connexion, index du canal, enrichissement
/// TMDB et préparation de la lecture.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:iptv/core/storage/app_storage.dart';
import 'package:iptv/features/telegram/data/telegram_channel_source.dart';
import 'package:iptv/features/telegram/data/telegram_service.dart';
import 'package:iptv/features/telegram/domain/telegram_media.dart';
import 'package:iptv/features/vod/data/tmdb_service.dart';
import 'package:iptv/features/vod/domain/media_entity.dart';

/// Une série reconstituée depuis les épisodes trouvés dans le canal.
class TelegramSeries {
  final String title;
  final List<TelegramMedia> episodes;

  const TelegramSeries({required this.title, required this.episodes});

  /// Saisons présentes, triées.
  List<int> get seasons =>
      episodes.map((e) => e.season).toSet().toList()..sort();

  List<TelegramMedia> episodesOf(int season) =>
      episodes.where((e) => e.season == season).toList()
        ..sort((a, b) => a.episode.compareTo(b.episode));
}

class TelegramProvider extends ChangeNotifier {
  final _service = TelegramService.instance;
  StreamSubscription<TelegramAuthState>? _authSub;

  // --- État ---
  TelegramAuthState _authState = TelegramAuthState.idle;
  String _channel = '';
  int _chatId = 0;
  List<TelegramMedia> _movies = [];
  List<TelegramSeries> _series = [];
  bool _isIndexing = false;
  int _indexProgress = 0;
  String _error = '';
  String _query = '';

  /// Fiches TMDB déjà résolues, indexées par clé titre+année. Mémoire seule :
  /// une session suffit, et ça évite de faire vieillir des affiches en cache.
  final _tmdbCache = <String, MediaEntity?>{};
  final _tmdbPending = <String, Future<MediaEntity?>>{};

  // --- Getters ---
  TelegramAuthState get authState => _authState;
  bool get isConfigured => TelegramService.isConfigured;
  bool get isReady => _authState == TelegramAuthState.ready;
  bool get hasChannel => _chatId != 0;
  String get channel => _channel;
  bool get isIndexing => _isIndexing;
  int get indexProgress => _indexProgress;
  String get error => _error;
  String get query => _query;

  /// Films filtrés par la recherche courante.
  List<TelegramMedia> get movies => _filterMovies();

  /// Séries filtrées par la recherche courante.
  List<TelegramSeries> get series => _filterSeries();

  bool get isEmpty => _movies.isEmpty && _series.isEmpty;

  // -------------------------------------------------------------------------
  // Cycle de vie
  // -------------------------------------------------------------------------

  Future<void> init() async {
    _channel = AppStorage.getTelegramChannel();
    _chatId = AppStorage.getTelegramChatId();

    _authSub ??= _service.authStates.listen((state) {
      _authState = state;
      if (state == TelegramAuthState.failed) _error = _service.lastError;
      if (state == TelegramAuthState.ready) _onReady();
      notifyListeners();
    });

    await _service.start();
    _authState = _service.authState;
    if (_authState == TelegramAuthState.failed) _error = _service.lastError;
    // Un service déjà démarré ne réémet pas son état : sans ce rattrapage,
    // rouvrir l'onglet après un dispose du provider afficherait une liste vide.
    if (_authState == TelegramAuthState.ready && isEmpty) unawaited(_onReady());
    notifyListeners();
  }

  /// À la connexion, on affiche immédiatement l'index en cache puis on
  /// rafraîchit en tâche de fond : l'utilisateur voit son catalogue tout de
  /// suite, même sur un canal de plusieurs milliers de fichiers.
  Future<void> _onReady() async {
    if (_chatId == 0) return;
    await _loadCached();
    unawaited(refreshIndex());
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Authentification
  // -------------------------------------------------------------------------

  Future<bool> submitPhone(String phone) => _auth(() =>
      _service.submitPhone(phone));

  Future<bool> submitCode(String code) => _auth(() =>
      _service.submitCode(code));

  Future<bool> submitPassword(String password) => _auth(() =>
      _service.submitPassword(password));

  Future<bool> _auth(Future<bool> Function() action) async {
    _error = '';
    notifyListeners();
    final ok = await action();
    if (!ok) {
      _error = _service.lastError;
      notifyListeners();
    }
    return ok;
  }

  Future<void> logOut() async {
    await _service.logOut();
    _movies = [];
    _series = [];
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Canal
  // -------------------------------------------------------------------------

  /// Résout et mémorise le canal, puis lance l'indexation.
  Future<bool> setChannel(String username) async {
    _error = '';
    _isIndexing = true;
    notifyListeners();

    final chatId = await _service.resolveChannel(username);
    if (chatId == null) {
      _error = _service.lastError.isNotEmpty
          ? _service.lastError
          : 'Canal introuvable.';
      _isIndexing = false;
      notifyListeners();
      return false;
    }

    _channel = username.trim().replaceFirst(RegExp(r'^@'), '');
    _chatId = chatId;
    await AppStorage.setTelegramChannel(_channel, chatId);
    await refreshIndex();
    return true;
  }

  Future<void> forgetChannel() async {
    if (_chatId != 0) await TelegramChannelSource.clearCache(_chatId);
    await AppStorage.clearTelegramChannel();
    _channel = '';
    _chatId = 0;
    _movies = [];
    _series = [];
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Index
  // -------------------------------------------------------------------------

  Future<void> _loadCached() async {
    if (_chatId == 0) return;
    _apply(await TelegramChannelSource.loadCached(_chatId));
  }

  Future<void> refreshIndex() async {
    if (_chatId == 0 || _isIndexing) return;
    _isIndexing = true;
    _indexProgress = 0;
    _error = '';
    notifyListeners();

    try {
      final media = await TelegramChannelSource.refresh(
        _chatId,
        onProgress: (found) {
          _indexProgress = found;
          notifyListeners();
        },
      );
      _apply(media);
    } catch (e) {
      _error = 'Indexation impossible : $e';
    } finally {
      _isIndexing = false;
      notifyListeners();
    }
  }

  /// Répartit l'index brut en films et séries regroupées.
  void _apply(List<TelegramMedia> media) {
    _movies = media.where((m) => !m.isEpisode).toList();

    final grouped = <String, List<TelegramMedia>>{};
    for (final m in media.where((m) => m.isEpisode)) {
      grouped.putIfAbsent(m.seriesKey, () => []).add(m);
    }
    _series = grouped.entries
        .map((e) => TelegramSeries(
              title: e.value.first.title,
              episodes: e.value,
            ))
        .toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Recherche
  // -------------------------------------------------------------------------

  void search(String query) {
    _query = query;
    notifyListeners();
  }

  List<TelegramMedia> _filterMovies() {
    if (_query.trim().isEmpty) return _movies;
    final q = _query.toLowerCase();
    return _movies
        .where((m) =>
            m.title.toLowerCase().contains(q) ||
            m.fileName.toLowerCase().contains(q))
        .toList();
  }

  List<TelegramSeries> _filterSeries() {
    if (_query.trim().isEmpty) return _series;
    final q = _query.toLowerCase();
    return _series.where((s) => s.title.toLowerCase().contains(q)).toList();
  }

  // -------------------------------------------------------------------------
  // Enrichissement TMDB
  // -------------------------------------------------------------------------

  /// Fiche déjà résolue, disponible sans attente.
  ///
  /// Sert d'`initialData` à la grille : un FutureBuilder repasse par un
  /// snapshot vide à chaque reconstruction, ce qui ferait clignoter les
  /// affiches à chaque scroll même quand la réponse est déjà connue.
  MediaEntity? cachedTmdb(TelegramMedia media) => _tmdbCache[_tmdbKey(media)];

  /// Fiche TMDB correspondant à un média, ou null si rien de convaincant.
  ///
  /// Résolue à la demande plutôt qu'en masse : un canal de 3000 fichiers
  /// déclencherait autant de requêtes TMDB au démarrage, pour des affiches que
  /// l'utilisateur ne verra jamais.
  Future<MediaEntity?> tmdbFor(TelegramMedia media) {
    final key = _tmdbKey(media);
    if (_tmdbCache.containsKey(key)) {
      return Future.value(_tmdbCache[key]);
    }
    // Dédoublonne les requêtes concurrentes : une grille affiche souvent
    // plusieurs épisodes d'une même série en même temps.
    return _tmdbPending.putIfAbsent(key, () async {
      final results = await TmdbService.search(media.title);
      final best = _bestMatch(results, media);
      _tmdbCache[key] = best;
      _tmdbPending.remove(key);
      return best;
    });
  }

  static String _tmdbKey(TelegramMedia m) =>
      '${m.title.toLowerCase()}|${m.isEpisode ? 'tv' : m.year}';

  /// Choisit le meilleur résultat TMDB pour un média du canal.
  ///
  /// La recherche multi de TMDB renvoie volontiers des suites et des
  /// documentaires homonymes. Le score privilégie, dans l'ordre : le bon type
  /// (série pour un épisode), le titre exact, puis l'année.
  @visibleForTesting
  static MediaEntity? bestMatch(
          List<MediaEntity> results, TelegramMedia media) =>
      _bestMatch(results, media);

  static MediaEntity? _bestMatch(
      List<MediaEntity> results, TelegramMedia media) {
    if (results.isEmpty) return null;
    final wanted = media.title.toLowerCase().trim();

    MediaEntity? best;
    var bestScore = -1;
    for (final r in results) {
      var score = 0;
      final isRightType = media.isEpisode ? r.isTv : r.isMovie;
      if (isRightType) score += 4;

      final title = r.title.toLowerCase().trim();
      if (title == wanted) {
        score += 4;
      } else if (title.startsWith(wanted) || wanted.startsWith(title)) {
        score += 2;
      }

      if (media.year > 0 && r.year.isNotEmpty) {
        final delta = (int.tryParse(r.year) ?? 0) - media.year;
        // Une année exacte confirme ; un écart d'un an reste plausible
        // (sortie décalée selon les pays), au-delà c'est une AUTRE œuvre.
        // La pénalité doit donc suffire à disqualifier seule, même avec un
        // titre exact : « The Thing » 1982 et 2011 sont deux films, et
        // afficher l'affiche de l'un pour l'autre est une erreur visible.
        if (delta == 0) {
          score += 3;
        } else if (delta.abs() <= 1) {
          score += 1;
        } else {
          score -= 6;
        }
      }

      if (score > bestScore) {
        bestScore = score;
        best = r;
      }
    }
    // En dessous de ce seuil, on préfère ne rien afficher qu'une affiche
    // fausse : un mauvais visuel est pire qu'un placeholder honnête.
    return bestScore >= 4 ? best : null;
  }

  // -------------------------------------------------------------------------
  // Lecture
  // -------------------------------------------------------------------------

  /// Octets contigus à obtenir avant d'ouvrir le lecteur. Assez pour que mpv
  /// trouve l'en-tête et démarre, sans faire attendre plusieurs minutes.
  static const _playableThreshold = 8 * 1024 * 1024;

  /// Démarre le téléchargement et émet la progression.
  Stream<TelegramDownload> prepare(TelegramMedia media) {
    unawaited(_service.startDownload(media.fileId));
    return _service.watchFile(media.fileId);
  }

  /// Vrai quand assez de données contiguës sont disponibles pour lancer mpv.
  bool canPlay(TelegramDownload download) =>
      download.isCompleted ||
      (download.isPlayable &&
          download.downloadedPrefixSize >= _playableThreshold);

  Future<void> cancel(TelegramMedia media) =>
      _service.cancelDownload(media.fileId);

  Future<void> removeFromDisk(TelegramMedia media) =>
      _service.deleteFile(media.fileId);
}
