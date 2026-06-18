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

  // Liste pré-vérifiée VIVANTE, régénérée toutes les 6h par la GitHub Action
  // tools/healthcheck.py (.github/workflows/healthcheck.yml). Sources 100%
  // légales uniquement. Chargée en 1er = chaînes les + fiables.
  static const String _verifiedIndex =
      'https://raw.githubusercontent.com/berlisB/iptv/main/verified.m3u';

  // Free streaming services (FAST/AVOD)
  // BuddyChewChew replaces old i.mjh.nz (DMCA'd by Warner Bros)
  static const String _buddyBase =
      'https://raw.githubusercontent.com/BuddyChewChew/app-m3u-generator/refs/heads/main/playlists';
  static const String _apsattBase = 'https://www.apsattv.com';

  static const List<String> _freeServices = [
    // Free-TV (politique anti-abonnement explicite, ~100 pays)
    'https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8',
    // freecasthub : UNIQUEMENT des endpoints CDN officiels (DW, France24, BBC
    // Arabic/Persian, VOA, Al Jazeera, CGTN). Licence Unlicense, la + propre.
    'https://raw.githubusercontent.com/freecasthub/public-iptv/main/playlist.m3u',
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
    // NOTE : i.mjh.nz/all/raw-tv.m3u8 retiré — DMCA'd par Warner Bros (08/2024),
    // renvoie 404. Remplacé par les broadcasters officiels ci-dessous.
  ];

  /// Tier 1 — HLS officiels des diffuseurs (les + fiables : CDN direct, pas de
  /// scraping, 100% légal/FTA). Flux uniques injectés comme un M3U curé.
  /// URL vérifiées 06/2026. En cas de rotation d'ID, iptv-org/api/streams.json
  /// les maintient à jour (sauf NASA, stable de son côté).
  static const String _officialBroadcasters = '''
#EXTM3U
#EXTINF:-1 tvg-id="NASATV.us" group-title="Officiel",NASA TV
https://ntv1.akamaized.net/hls/live/2014075/NASA-NTV1-HLS/master.m3u8
#EXTINF:-1 tvg-id="EuronewsEnglish.fr" group-title="Officiel",Euronews English
https://cdn-euronews.akamaized.net/live/eds/euronews-en/25002/index.m3u8
#EXTINF:-1 tvg-id="EuronewsFrench.fr" group-title="Officiel",Euronews Français
https://cdn-euronews.akamaized.net/live/eds/euronews-fr/25026/index.m3u8
#EXTINF:-1 tvg-id="DWEnglish.de" group-title="Officiel",DW English
https://dwamdstream102.akamaized.net/hls/live/2015525/dwstream102/master.m3u8
#EXTINF:-1 tvg-id="France24English.fr" group-title="Officiel",France 24 English
https://live.france24.com/hls/live/2037218/F24_EN_HI_HLS/master_5000.m3u8
#EXTINF:-1 tvg-id="France24French.fr" group-title="Officiel",France 24 Français
https://live.france24.com/hls/live/2037179/F24_FR_HI_HLS/master_5000.m3u8
#EXTINF:-1 tvg-id="AlJazeeraEnglish.qa" group-title="Officiel",Al Jazeera English
https://live-hls-web-aje.getaj.net/AJE/index.m3u8
#EXTINF:-1 tvg-id="AlJazeera.qa" group-title="Officiel",Al Jazeera Arabic
https://live-hls-web-aja.getaj.net/AJA-V3/index.m3u8
#EXTINF:-1 tvg-id="ABCNewsLive.us" group-title="Officiel",ABC News Live
https://abcnews-streams.akamaized.net/hls/live/2023560/abcnewshudson1/master.m3u8
''';

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

  /// Fetch la liste pré-vérifiée vivante (régénérée toutes les 6h par CI).
  /// Vide tant que la 1ère Action n'a pas tourné — non bloquant.
  static Future<String> fetchVerifiedIndex() async {
    final result = await _fetchPlaylist(_verifiedIndex);
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
        fetchVerifiedIndex(), // pré-vérifiées vivantes (en 1er = + fiables)
        fetchMasterIndex(),
        fetchFreeServices(),
      ]).timeout(const Duration(seconds: 60));

      for (final result in results) {
        if (result.length > 100) {
          parts.add(result);
        }
      }

      // Tier 1 broadcasters officiels : toujours inclus (curé, hors réseau).
      parts.add(_officialBroadcasters);
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
