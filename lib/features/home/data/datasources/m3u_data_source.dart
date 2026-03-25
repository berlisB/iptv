import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class M3uDataSource {
  M3uDataSource._();

  // Local assets
  static const String _frPlaylist = 'assets/playlists/fr.m3u';
  static const String _internationalPlaylist = 'assets/playlists/international.m3u8';
  static const String _blocklistAsset = 'assets/playlists/blocklist.json';

  // iptv-org remote source
  static const String _iptvOrgBase =
      'https://iptv-org.github.io/iptv/countries';

  // Default countries to fetch
  static const List<String> defaultCountries = [
    'fr', 'us', 'gb', 'de', 'es', 'it', 'pt', 'br', 'ca', 'be',
    'ch', 'ma', 'dz', 'tn', 'sn', 'ci', 'cm', 'cd', 'jp', 'kr',
    'in', 'tr', 'ru', 'ae', 'sa', 'eg', 'ng', 'za', 'au', 'mx',
    'ar', 'co', 'cl', 'pl', 'nl', 'se', 'no', 'dk', 'fi', 'gr',
  ];

  /// Fetch M3U playlist from iptv-org for a specific country
  static Future<String?> fetchCountryPlaylist(String countryCode) async {
    try {
      final url = '$_iptvOrgBase/$countryCode.m3u';
      debugPrint('[IPTV] Fetching $url');
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        debugPrint(
            '[IPTV] Got ${response.body.length} bytes for $countryCode');
        return response.body;
      }
    } catch (e) {
      debugPrint('[IPTV] Failed to fetch $countryCode: $e');
    }
    return null;
  }

  /// Fetch multiple countries in parallel
  static Future<String> fetchCountries(List<String> countryCodes) async {
    final futures = countryCodes.map((code) => fetchCountryPlaylist(code));
    final results = await Future.wait(futures);
    return results.where((r) => r != null).join('\n');
  }

  /// Load local playlists as fallback
  static Future<String> loadLocalPlaylists() async {
    final fr = await rootBundle.loadString(_frPlaylist);
    final intl = await rootBundle.loadString(_internationalPlaylist);
    return '$fr\n$intl';
  }

  /// Load all: try remote first, fallback to local
  static Future<String> loadAllPlaylists() async {
    try {
      final remote = await fetchCountries(defaultCountries);
      if (remote.length > 1000) {
        // Also load local for extra channels
        final local = await loadLocalPlaylists();
        return '$remote\n$local';
      }
    } catch (e) {
      debugPrint('[IPTV] Remote fetch failed, using local: $e');
    }
    return loadLocalPlaylists();
  }

  /// Load blocklist of known broken URLs
  static Future<Set<String>> loadBlocklist() async {
    try {
      final raw = await rootBundle.loadString(_blocklistAsset);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final urls = (json['urls'] as List).cast<String>();
      debugPrint('[IPTV] Loaded blocklist: ${urls.length} broken URLs');
      return urls.toSet();
    } catch (e) {
      debugPrint('[IPTV] Failed to load blocklist: $e');
      return {};
    }
  }
}
