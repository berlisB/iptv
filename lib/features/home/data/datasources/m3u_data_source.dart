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

  // iptv-org master index (ALL channels in one file, ~8000+)
  static const String _masterIndex =
      'https://iptv-org.github.io/iptv/index.m3u';

  // Free streaming services (FAST/AVOD)
  // BuddyChewChew replaces old i.mjh.nz (DMCA'd by Warner Bros)
  static const String _buddyBase =
      'https://raw.githubusercontent.com/BuddyChewChew/app-m3u-generator/refs/heads/main/playlists';
  static const String _apsattBase = 'https://www.apsattv.com';

  static const List<String> _freeServices = [
    // Free-TV
    'https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8',
    // BuddyChewChew (Pluto, Samsung, Plex, Roku, Tubi)
    '$_buddyBase/plutotv_all.m3u',
    '$_buddyBase/samsungtvplus_all.m3u',
    '$_buddyBase/plex_all.m3u',
    '$_buddyBase/roku_all.m3u',
    '$_buddyBase/tubi_all.m3u',
    // Xumo
    'https://raw.githubusercontent.com/BuddyChewChew/xumo-playlist-generator/refs/heads/main/playlists/xumo_playlist.m3u',
    // apsattv.com FAST services
    '$_apsattBase/distro.m3u',
    '$_apsattBase/localnow.m3u',
    '$_apsattBase/vidaa.m3u',
    '$_apsattBase/vizio.m3u',
    '$_apsattBase/tclplus.m3u',
    // LG Channels France
    '$_apsattBase/frlg.m3u',
    // Freeview NZ/AU
    'https://i.mjh.nz/all/raw-tv.m3u8',
  ];

  /// Fetch a single remote playlist
  static Future<String?> _fetchPlaylist(String url) async {
    try {
      debugPrint('[IPTV] Fetching $url');
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 && response.body.length > 100) {
        debugPrint('[IPTV] Got ${response.body.length} bytes from $url');
        return response.body;
      }
    } catch (e) {
      debugPrint('[IPTV] Failed: $url ($e)');
    }
    return null;
  }

  /// Fetch iptv-org master index (all 8000+ channels in 1 request)
  static Future<String> fetchMasterIndex() async {
    final result = await _fetchPlaylist(_masterIndex);
    return result ?? '';
  }

  /// Fetch free streaming services in parallel (non-blocking)
  static Future<String> fetchFreeServices() async {
    // Use individual timeouts per fetch (already 30s each in _fetchPlaylist).
    // Don't let one slow source block others.
    final futures = _freeServices.map((url) =>
        _fetchPlaylist(url).catchError((_) => null as String?));
    final results = await Future.wait(futures);
    final loaded = results.where((r) => r != null).length;
    debugPrint('[IPTV] Free services: $loaded/${_freeServices.length} loaded');
    return results.where((r) => r != null).join('\n');
  }

  /// Load local playlists as fallback
  static Future<String> loadLocalPlaylists() async {
    final fr = await rootBundle.loadString(_frPlaylist);
    final intl = await rootBundle.loadString(_internationalPlaylist);
    return '$fr\n$intl';
  }

  /// Load all sources
  static Future<String> loadAllPlaylists() async {
    final parts = <String>[];

    try {
      final results = await Future.wait([
        fetchMasterIndex(),
        fetchFreeServices(),
      ]).timeout(const Duration(seconds: 60));

      for (final result in results) {
        if (result.length > 100) {
          parts.add(result);
        }
      }
    } catch (e) {
      debugPrint('[IPTV] Remote fetch error: $e');
    }

    // Always include local as fallback
    try {
      parts.add(await loadLocalPlaylists());
    } catch (e) {
      debugPrint('[IPTV] Local load error: $e');
    }

    debugPrint('[IPTV] Total playlist data: '
        '${parts.fold<int>(0, (sum, p) => sum + p.length)} bytes');

    return parts.join('\n');
  }

  /// Load blocklist
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
