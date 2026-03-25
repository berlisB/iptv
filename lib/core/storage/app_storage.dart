import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

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

  static Future<void> addToBlocklist(String url) async {
    final list = _prefs.getStringList(_localBlocklistKey) ?? [];
    if (!list.contains(url)) {
      list.add(url);
      await _prefs.setStringList(_localBlocklistKey, list);
    }
  }

  static Future<void> removeFromBlocklist(String url) async {
    final list = _prefs.getStringList(_localBlocklistKey) ?? [];
    list.remove(url);
    await _prefs.setStringList(_localBlocklistKey, list);
  }

  static Future<void> clearLocalBlocklist() async {
    await _prefs.remove(_localBlocklistKey);
  }

  // Volume
  static const String _volumeKey = 'volume';

  static Future<void> setVolume(double volume) async {
    await _prefs.setDouble(_volumeKey, volume);
  }

  static double getVolume() {
    return _prefs.getDouble(_volumeKey) ?? 100.0;
  }
}
