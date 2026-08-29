import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iptv/core/catalog/curation_config.dart';

class AppStorage {
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Favorites
  static const String _favoritesKey = 'favorites';

  static List<String> getFavorites() {
    return _prefs.getStringList(_favoritesKey) ?? [];
  }

  static Future<void> addFavorite(String channelId) async {
    final favorites = getFavorites();
    if (!favorites.contains(channelId)) {
      favorites.add(channelId);
      await _prefs.setStringList(_favoritesKey, favorites);
    }
  }

  static Future<void> removeFavorite(String channelId) async {
    final favorites = getFavorites();
    favorites.remove(channelId);
    await _prefs.setStringList(_favoritesKey, favorites);
  }

  static bool isFavorite(String channelId) {
    return getFavorites().contains(channelId);
  }

  // Recent channels (ordered, most recent first, max 20)
  static const String _recentKey = 'recent_channels';

  static List<String> getRecentChannels() {
    return _prefs.getStringList(_recentKey) ?? [];
  }

  static Future<void> addRecentChannel(String channelId) async {
    final recents = getRecentChannels();
    recents.remove(channelId);
    recents.insert(0, channelId);
    if (recents.length > 20) recents.removeLast();
    await _prefs.setStringList(_recentKey, recents);
  }

  // Watch count per channel (for "frequent" section)
  static const String _watchCountKey = 'watch_counts';

  static Map<String, int> getWatchCounts() {
    final raw = _prefs.getString(_watchCountKey);
    if (raw == null) return {};
    return Map<String, int>.from(jsonDecode(raw));
  }

  static Future<void> incrementWatchCount(String channelId) async {
    final counts = getWatchCounts();
    counts[channelId] = (counts[channelId] ?? 0) + 1;
    await _prefs.setString(_watchCountKey, jsonEncode(counts));
  }

  static List<String> getFrequentChannels({int limit = 10}) {
    final counts = getWatchCounts();
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).map((e) => e.key).toList();
  }

  // Broken/hidden channels
  static const String _hiddenKey = 'hidden_channels';

  static List<String> getHiddenChannels() {
    return _prefs.getStringList(_hiddenKey) ?? [];
  }

  static Future<void> hideChannel(String channelId) async {
    final hidden = getHiddenChannels();
    if (!hidden.contains(channelId)) {
      hidden.add(channelId);
      await _prefs.setStringList(_hiddenKey, hidden);
    }
  }

  static Future<void> unhideChannel(String channelId) async {
    final hidden = getHiddenChannels();
    hidden.remove(channelId);
    await _prefs.setStringList(_hiddenKey, hidden);
  }

  static Future<void> clearHiddenChannels() async {
    await _prefs.remove(_hiddenKey);
  }

  static bool isHidden(String channelId) {
    return getHiddenChannels().contains(channelId);
  }

  // Local blocklist (broken URLs detected at runtime)
  static const String _localBlocklistKey = 'local_blocklist';

  static Set<String> getLocalBlocklist() {
    return (_prefs.getStringList(_localBlocklistKey) ?? []).toSet();
  }

  static Future<void> clearLocalBlocklist() async {
    await _prefs.remove(_localBlocklistKey);
  }

  // Settings toggles
  static bool getShowAdult() => _prefs.getBool('show_adult') ?? false;
  static Future<void> setShowAdult(bool v) => _prefs.setBool('show_adult', v);

  static bool getShowGeoBlocked() => _prefs.getBool('show_geo') ?? false;
  static Future<void> setShowGeoBlocked(bool v) => _prefs.setBool('show_geo', v);

  static bool getShowHidden() => _prefs.getBool('show_hidden') ?? false;
  static Future<void> setShowHidden(bool v) => _prefs.setBool('show_hidden', v);

  // Buffer level: 0=low, 1=normal (default), 2=high
  static const String _bufferLevelKey = 'buffer_level';
  static int getBufferLevel() => _prefs.getInt(_bufferLevelKey) ?? 1;
  static Future<void> setBufferLevel(int v) => _prefs.setInt(_bufferLevelKey, v);

  // Confirmed (reliable) channels
  static const String _confirmedKey = 'confirmed_channels';

  static Set<String> getConfirmedChannels() {
    return (_prefs.getStringList(_confirmedKey) ?? []).toSet();
  }

  static bool isConfirmed(String channelId) {
    return getConfirmedChannels().contains(channelId);
  }

  static Future<void> confirmChannel(String channelId) async {
    final list = _prefs.getStringList(_confirmedKey) ?? [];
    if (!list.contains(channelId)) {
      list.add(channelId);
      await _prefs.setStringList(_confirmedKey, list);
    }
  }

  static Future<void> unconfirmChannel(String channelId) async {
    final list = _prefs.getStringList(_confirmedKey) ?? [];
    list.remove(channelId);
    await _prefs.setStringList(_confirmedKey, list);
  }

  static Future<void> clearConfirmedChannels() async {
    await _prefs.remove(_confirmedKey);
    await _prefs.remove(_confirmedAtKey);
  }

  // --- Fraîcheur des chaînes fiables (decay) ---
  // Une chaîne confirmée "fiable" il y a plus de 7 jours doit être re-testée.
  static const String _confirmedAtKey = 'confirmed_at';
  static const int _reliableTtlMs = 7 * 24 * 60 * 60 * 1000;

  static Map<String, int> _getConfirmedAt() {
    final raw = _prefs.getString(_confirmedAtKey);
    if (raw == null) return {};
    return Map<String, int>.from(jsonDecode(raw));
  }

  // Mémorise l'instant de confirmation pour pouvoir faire expirer la fiabilité.
  static Future<void> markConfirmedNow(String channelId) async {
    final map = _getConfirmedAt();
    map[channelId] = DateTime.now().millisecondsSinceEpoch;
    await _prefs.setString(_confirmedAtKey, jsonEncode(map));
  }

  // Retourne true si la confirmation est encore fraîche (< TTL).
  static bool isReliableFresh(String channelId, {int? nowMs}) {
    final at = _getConfirmedAt()[channelId];
    if (at == null) return true; // ancienne confirmation sans date → on garde
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return (now - at) < _reliableTtlMs;
  }

  // --- Strikes : échecs DURS répétés (403/404/codec/DNS), jamais la lenteur ---
  static const String _strikesKey = 'channel_strikes';
  static const int strikeThreshold = 3; // banni seulement au-delà

  static Map<String, int> _getStrikes() {
    final raw = _prefs.getString(_strikesKey);
    if (raw == null) return {};
    return Map<String, int>.from(jsonDecode(raw));
  }

  static int getStrikes(String channelId) => _getStrikes()[channelId] ?? 0;

  // Ajoute un strike (échec dur) et renvoie le nouveau total.
  static Future<int> addStrike(String channelId) async {
    final map = _getStrikes();
    final next = (map[channelId] ?? 0) + 1;
    map[channelId] = next;
    await _prefs.setString(_strikesKey, jsonEncode(map));
    return next;
  }

  // Remet les strikes à zéro dès qu'une chaîne refonctionne (decay au succès).
  static Future<void> resetStrikes(String channelId) async {
    final map = _getStrikes();
    if (map.remove(channelId) != null) {
      await _prefs.setString(_strikesKey, jsonEncode(map));
    }
  }

  // Une chaîne n'est considérée "morte" qu'après strikeThreshold échecs durs.
  static bool isDead(String channelId) =>
      getStrikes(channelId) >= strikeThreshold;

  // --- Score de fiabilité (0..100, decay graduel) ---------------------------
  // Complète les "strikes" (binaire mort/vivant) par un score continu utilisé
  // pour classer et masquer. Règles centralisées dans CurationConfig.
  static const String _scoreKey = 'reliability_scores';
  static const String _checkedAtKey = 'reliability_checked_at';

  static Map<String, int> _getScores() {
    final raw = _prefs.getString(_scoreKey);
    if (raw == null) return {};
    return Map<String, int>.from(jsonDecode(raw));
  }

  /// Score courant d'une chaîne (valeur initiale si jamais testée).
  static int getScore(String channelId) =>
      _getScores()[channelId] ?? CurationConfig.initialScore;

  static Future<void> _applyDelta(String channelId, int delta) async {
    final map = _getScores();
    final current = map[channelId] ?? CurationConfig.initialScore;
    map[channelId] = CurationConfig.clampScore(current + delta);
    await _prefs.setString(_scoreKey, jsonEncode(map));
    await _markChecked(channelId);
  }

  /// Lecture/probe réussie → on récompense (et on efface les strikes).
  static Future<void> recordSuccess(String channelId) async {
    await _applyDelta(channelId, CurationConfig.rewardSuccess);
    await resetStrikes(channelId);
  }

  /// Échec mou (injoignable/transitoire) → pénalité douce.
  static Future<void> recordSoftFail(String channelId) =>
      _applyDelta(channelId, -CurationConfig.penaltySoftFail);

  /// Timeout → pénalité moyenne.
  static Future<void> recordTimeout(String channelId) =>
      _applyDelta(channelId, -CurationConfig.penaltyTimeout);

  /// Échec dur (403/404/410/codec) → forte pénalité + strike.
  static Future<void> recordHardFail(String channelId) async {
    await _applyDelta(channelId, -CurationConfig.penaltyHardFail);
    await addStrike(channelId);
  }

  // Horodatage de la dernière vérification de flux.
  static Map<String, int> _getCheckedAtMap() {
    final raw = _prefs.getString(_checkedAtKey);
    if (raw == null) return {};
    return Map<String, int>.from(jsonDecode(raw));
  }

  static Future<void> _markChecked(String channelId) async {
    final map = _getCheckedAtMap();
    map[channelId] = DateTime.now().millisecondsSinceEpoch;
    await _prefs.setString(_checkedAtKey, jsonEncode(map));
  }

  /// Dernière vérification connue (null = jamais testée).
  static DateTime? getCheckedAt(String channelId) {
    final ms = _getCheckedAtMap()[channelId];
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  // --- Abonnement Xtream Codes (optionnel) ---
  static const String _xtreamKey = 'xtream_config';

  // Retourne {host, username, password} ou null si non configuré.
  static Map<String, String>? getXtreamConfig() {
    final raw = _prefs.getString(_xtreamKey);
    if (raw == null) return null;
    return Map<String, String>.from(jsonDecode(raw));
  }

  static Future<void> setXtreamConfig(
      String host, String username, String password) async {
    await _prefs.setString(
      _xtreamKey,
      jsonEncode({'host': host, 'username': username, 'password': password}),
    );
  }

  static Future<void> clearXtreamConfig() async {
    await _prefs.remove(_xtreamKey);
  }

  // --- Source Daddylive (optionnelle, étude éducative) ---
  static const String _daddyliveEnabledKey = 'daddylive_enabled';

  static bool getDaddyliveEnabled() =>
      _prefs.getBool(_daddyliveEnabledKey) ?? false;

  static Future<void> setDaddyliveEnabled(bool v) async {
    await _prefs.setBool(_daddyliveEnabledKey, v);
  }

  /// Flag pour savoir si les données player ont déjà été chargées en cache.
  static const String _daddyliveCachedKey = 'daddylive_cached_at';

  static int getDaddyliveCachedAt() =>
      _prefs.getInt(_daddyliveCachedKey) ?? 0;

  static Future<void> setDaddyliveCachedAt() async {
    await _prefs.setInt(
        _daddyliveCachedKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Le cache expire après 1h.
  static bool get isDaddyliveCacheFresh {
    final age = DateTime.now().millisecondsSinceEpoch - getDaddyliveCachedAt();
    return age < 3600000; // 1h
  }

  // --- Historique VOD (films/séries/animés) ---
  static const String _vodProgressKey = 'vod_progress';
  static const String _vodWatchedKey = 'vod_watched';

  /// Map<tmdbId, {season, episode, timestamp}>.
  static Map<String, Map<String, dynamic>> _getVodProgress() {
    final raw = _prefs.getString(_vodProgressKey);
    if (raw == null) return {};
    final decoded = jsonDecode(raw);
    return (decoded as Map).map((k, v) =>
        MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)));
  }

  /// Sauvegarde la progression de lecture (dernier épisode regardé).
  static Future<void> saveWatchProgress(int tmdbId,
      {required int season, required int episode}) async {
    final map = _getVodProgress();
    map['$tmdbId'] = {
      'season': season,
      'episode': episode,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
    await _prefs.setString(_vodProgressKey, jsonEncode(map));
  }

  /// Récupère la progression de lecture d'une série. Retourne null si aucune.
  static Map<String, int>? getWatchProgress(int tmdbId) {
    final entry = _getVodProgress()['$tmdbId'];
    if (entry == null) return null;
    return {
      'season': entry['season'] as int,
      'episode': entry['episode'] as int,
    };
  }

  /// Set<episodeNumber> des épisodes déjà vus pour une sériedonnée.
  static Set<int> getWatchedEpisodes(int tmdbId, {required int season}) {
    final raw = _prefs.getString('${_vodWatchedKey}_$tmdbId');
    if (raw == null) return {};
    final all = Map<String, bool>.from(jsonDecode(raw));
    final prefix = '$season:';
    return all.entries
        .where((e) => e.value && e.key.startsWith(prefix))
        .map((e) => int.tryParse(e.key.substring(prefix.length)))
        .whereType<int>()
        .toSet();
  }

  /// Marque un épisode comme vu (ou non vu si `watched=false`).
  static Future<void> setEpisodeWatched(int tmdbId,
      {required int season,
      required int episode,
      bool watched = true}) async {
    final key = '${_vodWatchedKey}_$tmdbId';
    final raw = _prefs.getString(key);
    final all = raw != null
        ? Map<String, bool>.from(jsonDecode(raw))
        : <String, bool>{};
    all['$season:$episode'] = watched;
    await _prefs.setString(key, jsonEncode(all));
  }

  /// Nombre d'épisodes vus dans une saison.
  static int countWatchedInSeason(int tmdbId, int season) {
    return getWatchedEpisodes(tmdbId, season: season).length;
  }
}
