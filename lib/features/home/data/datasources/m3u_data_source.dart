import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:iptv/core/services/disk_cache.dart';
import 'package:iptv/core/utils/stable_id.dart';

/// Sources M3U brutes du mode « Explorer ». Le mode « Sélection fiable » est
/// servi par le catalogue v3 (CatalogV3Source) — les flux vérifiés par la CI
/// n'ont plus à être re-téléchargés ici.
class M3uDataSource {
  M3uDataSource._();

  // Local assets
  static const String _frPlaylist = 'assets/playlists/fr.m3u';
  static const String _internationalPlaylist = 'assets/playlists/international.m3u8';
  static const String _blocklistAsset = 'assets/playlists/blocklist.json';

  static const Duration _cacheTtl = Duration(hours: 6);

  // iptv-org : SEULEMENT les chaînes françaises (472 chaînes, pas le master 8000+)
  static const String _iptvOrgFrench =
      'https://iptv-org.github.io/iptv/languages/fra.m3u';

  // --- Sources Fiables (françaises + internationales officielles) ---
  static const List<String> _reliableSources = [
    // Free-TV France (chaînes françaises officielles)
    'https://raw.githubusercontent.com/Free-TV/IPTV/master/streams/fr.m3u',
    // freecasthub : UNIQUEMENT des endpoints CDN officiels (DW, France24, BBC)
    'https://raw.githubusercontent.com/freecasthub/public-iptv/main/playlist.m3u',
    // LG Channels France (chaînes françaises via LG FAST)
    'https://www.apsattv.com/frlg.m3u',
  ];

  // --- Sources IPTV Chine (box chinoises) ---
  // CDN Mobile/Unicom/Telecom + sources communautaires GitHub
  static const List<String> _chineseIptvSources = [
    // CCSH/IPTV : CCTV + régions, mise à jour auto, logo + EPG
    'https://raw.githubusercontent.com/CCSH/IPTV/refs/heads/main/live.m3u',
    // vbskycn/iptv :央视+卫视+地方台, IPv4, auto-scanné toutes les 6h
    'https://live.zbds.top/tv/iptv4.m3u',
    // fanmingming/live : source communautaire populaire
    'https://raw.githubusercontent.com/fanmingming/live/main/tv/m3u/ipv6.m3u',
    // yifoo/autoiptv :精简合并版央视+卫视
    'https://raw.githubusercontent.com/yifoo/autoiptv/main/merged/%E7%B2%BE%E7%AE%80%E7%89%88.m3u',
    // BurningC4/Chinese-IPTV : CCTV IPV4
    'https://raw.githubusercontent.com/BurningC4/Chinese-IPTV/main/tv.m3u',
  ];

  /// Fetch une playlist avec cache disque : cache frais (< 6 h) → réseau →
  /// cache périmé en secours si le réseau échoue.
  static Future<String?> _fetchPlaylist(String url) async {
    final cacheKey = 'm3u_${fnv1a64Hex(url)}';
    final cached = await DiskCache.readString(cacheKey, maxAge: _cacheTtl);
    if (cached != null) {
      debugPrint('[IPTV] Cache hit: $url');
      return cached;
    }
    try {
      debugPrint('[IPTV] Fetching $url');
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 && response.body.length > 100) {
        debugPrint('[IPTV] Got ${response.body.length} bytes from $url');
        await DiskCache.writeString(cacheKey, response.body);
        return response.body;
      }
    } catch (e) {
      debugPrint('[IPTV] Failed: $url ($e)');
    }
    final stale = await DiskCache.readString(cacheKey);
    if (stale != null) debugPrint('[IPTV] Réseau KO → cache périmé: $url');
    return stale;
  }

  /// Fetch les chaînes françaises iptv-org (472 chaînes, pas le master 8000+)
  static Future<String> fetchIptvOrgFrench() async {
    final result = await _fetchPlaylist(_iptvOrgFrench);
    return result ?? '';
  }

  /// Fetch les sources fiables (françaises + CDN officiels)
  static Future<String> fetchReliableSources() async {
    final futures = _reliableSources.map((url) =>
        _fetchPlaylist(url).catchError((_) => null as String?));
    final results = await Future.wait(futures);
    final loaded = results.where((r) => r != null).length;
    debugPrint('[IPTV] Reliable: $loaded/${_reliableSources.length} loaded');
    return results.where((r) => r != null).join('\n');
  }

  /// Fetch sources IPTV chinoises (CDN Mobile/Unicom/Telecom + GitHub)
  static Future<String> fetchChineseIptv() async {
    final futures = _chineseIptvSources.map((url) =>
        _fetchPlaylist(url).catchError((_) => null as String?));
    final results = await Future.wait(futures);
    final loaded = results.where((r) => r != null).length;
    debugPrint('[IPTV] Chinese IPTV: $loaded/${_chineseIptvSources.length} loaded');
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
        fetchIptvOrgFrench(),       // chaînes françaises iptv-org
        fetchReliableSources(),     // sources fiables (françaises + CDN officiels)
        fetchChineseIptv(),         // IPTV chinoises (CCTV + régions)
      ]).timeout(const Duration(seconds: 60));

      for (final result in results) {
        if (result.length > 100) {
          parts.add(result);
        }
      }
    } catch (e) {
      debugPrint('[IPTV] Remote fetch error: $e');
    }

    // Assets embarqués : uniquement en secours quand tout le réseau a échoué
    // (sinon ils ne créent que des doublons périmés).
    if (parts.isEmpty) {
      try {
        parts.add(await loadLocalPlaylists());
        debugPrint('[IPTV] Réseau KO → playlists embarquées');
      } catch (e) {
        debugPrint('[IPTV] Local load error: $e');
      }
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
