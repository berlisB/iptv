import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:iptv/features/home/domain/entities/channel_entity.dart';

/// Résultat du scraping d'une page embed Daddylive.
@visibleForTesting
class DaddyliveScrapeResult {
  final List<Map<String, String>> playerEntries;
  final List<String> m3u8Urls;
  DaddyliveScrapeResult(this.playerEntries, this.m3u8Urls);
}

class DaddyliveService {
  DaddyliveService._();

  static const String _baseUrl = 'https://daddylive.org';
  static const String _apiChannels = '$_baseUrl/api/channels';
  static const String _apiEvents = '$_baseUrl/api/events';

  /// Nombre de players à essayer (1-15).
  static const List<int> _players = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

  /// Timeout par requête.
  static const _timeout = Duration(seconds: 20);

  /// Headers HTTP requis pour les requêtes daddylive.
  static Map<String, String> get _headers => {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/120.0.0.0 Safari/537.36',
        'Referer': '$_baseUrl/',
        'Accept': 'application/json, text/html, */*',
      };

  // ---------------------------------------------------------------------------
  //  API: liste des chaînes
  // ---------------------------------------------------------------------------

  /// Récupère la liste des chaînes depuis `/api/channels`.
  /// Renvoie une liste de maps {channel_name, channel_id, url}.
  static Future<List<Map<String, dynamic>>> fetchChannels() async {
    try {
      debugPrint('[Daddylive] Fetching channels from /api/channels');
      final resp = await http
          .get(Uri.parse(_apiChannels), headers: _headers)
          .timeout(_timeout);
      if (resp.statusCode != 200) {
        debugPrint('[Daddylive] /api/channels returned ${resp.statusCode}');
        return [];
      }
      final body = resp.body.trim();
      if (!body.startsWith('[')) {
        debugPrint('[Daddylive] /api/channels not JSON array');
        return [];
      }
      final list = jsonDecode(body) as List;
      debugPrint('[Daddylive] ${list.length} channels from API');
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[Daddylive] fetchChannels error: $e');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  //  Scraper: extrait les données player + URLs M3U8 depuis l'embed
  // ---------------------------------------------------------------------------

    /// Extrait les données player d'une page embed.
  @visibleForTesting
  static DaddyliveScrapeResult extractPlayerData(String html) {
    final entries = <Map<String, String>>[];
    final allM3u8 = <String>{};

    // Extrait player{1-15}Data JSON
    for (final player in _players) {
      final pattern = RegExp(
        r'const\s+player' + player.toString() + r'Data\s*=\s*(\[[\s\S]*?\])\s*;',
      );
      final match = pattern.firstMatch(html);
      if (match == null) continue;
      try {
        final data = jsonDecode(match.group(1)!) as List;
        for (final entry in data) {
          final name = '${entry['name'] ?? ''}'.trim();
          final url = '${entry['url'] ?? ''}'.trim();
          if (name.isNotEmpty && url.isNotEmpty) {
            entries.add({'name': name, 'url': url});
          }
        }
      } catch (_) {}
    }

    // Extrait toutes les URLs M3U8 du HTML
    final m3u8Regex = RegExp(
      r'https?://[^"<>\s]+\.m3u8[^"<>\s]*',
    );
    for (final m in m3u8Regex.allMatches(html)) {
      allM3u8.add(m.group(0)!);
    }

    return DaddyliveScrapeResult(entries, allM3u8.toList());
  }

  /// Scrape une page embed pour récupérer les données player.
  static Future<DaddyliveScrapeResult> scrapeEmbed({
    String channelId = '32',
    List<int> players = const [1, 5],
  }) async {
    final allEntries = <Map<String, String>>[];
    final allM3u8 = <String>{};

    for (final player in players) {
      try {
        final url =
            '$_baseUrl/embed/embed.php?id=$channelId&player=$player&source=tv.json';
        final resp = await http
            .get(Uri.parse(url), headers: _headers)
            .timeout(_timeout);
        if (resp.statusCode != 200) continue;

        final result = extractPlayerData(resp.body);
        allEntries.addAll(result.playerEntries);
        allM3u8.addAll(result.m3u8Urls);
      } catch (e) {
        debugPrint('[Daddylive] scrapeEmbed player=$player error: $e');
      }
    }

    return DaddyliveScrapeResult(allEntries, allM3u8.toList());
  }

  // ---------------------------------------------------------------------------
  //  Conversion en ChannelEntity
  // ---------------------------------------------------------------------------

  /// Convertit la liste API + données player en [ChannelEntity].
  /// Utilise les mappings des données player pour trouver l'URL de stream.
  static List<ChannelEntity> toChannelEntities(
    List<Map<String, dynamic>> apiChannels,
    DaddyliveScrapeResult scrapeResult,
  ) {
    if (apiChannels.isEmpty) return [];

    // Indexe les entrées player par nom (normalisé)
    final playerIndex = <String, List<Map<String, String>>>{};
    for (final entry in scrapeResult.playerEntries) {
      final key = _normalizeName(entry['name']!);
      playerIndex.putIfAbsent(key, () => []).add(entry);
    }

    final channels = <ChannelEntity>[];
    final seenUrls = <String>{};

    for (final api in apiChannels) {
      final name = '${api['channel_name'] ?? ''}'.trim();
      final id = '${api['channel_id'] ?? ''}'.trim();
      if (name.isEmpty || id.isEmpty) continue;

      // Cherche une URL dans les données player
      final playerKey = _normalizeName(name);
      final playerMatch = playerIndex[playerKey];
      String? streamUrl;
      if (playerMatch != null && playerMatch.isNotEmpty) {
        streamUrl = playerMatch.first['url'];
      }

      // Fallback: utilise l'embed URL comme URL de stream (avec headers)
      final embedUrl = '$_baseUrl/embed/embed.php?id=$id&player=1&source=tv.json';

      // Évite les doublons d'URL
      final primaryUrl = streamUrl ?? embedUrl;
      if (seenUrls.contains(primaryUrl)) continue;
      seenUrls.add(primaryUrl);

      // M3U8 URLs from scrape result as backup
      final backupUrls = scrapeResult.m3u8Urls
          .where((u) => !seenUrls.contains(u))
          .take(3)
          .toList();
      for (final u in backupUrls) {
        seenUrls.add(u);
      }

      // Détecte le pays depuis le nom (ex: "TNT Sports 2 UK" → "UK")
      final country = _detectCountry(name);

      // Détecte la catégorie
      final category = _detectCategory(name);
      final isSport = category == 'Sport';

      channels.add(ChannelEntity(
        id: 'daddylive_$id',
        name: name,
        url: primaryUrl,
        backupUrls: backupUrls,
        group: isSport ? 'Sport' : 'Daddylive',
        country: country,
        category: category,
        sourceType: SourceType.communityUnverified,
        httpHeaders: const ChannelHttpHeaders(
          referrer: '$_baseUrl/',
        ),
        priority: isSport ? 1 : 2,
      ));
    }

    debugPrint('[Daddylive] Converted ${channels.length} channels');
    return channels;
  }

  // ---------------------------------------------------------------------------
  //  Génération M3U
  // ---------------------------------------------------------------------------

  /// Génère un M3U à partir des données player.
  static String generateM3U(DaddyliveScrapeResult scrapeResult) {
    final buf = StringBuffer('#EXTM3U\n');
    final seen = <String>{};
    for (final entry in scrapeResult.playerEntries) {
      final name = entry['name']!;
      final url = entry['url']!;
      if (seen.contains(url)) continue;
      seen.add(url);
      buf.writeln('#EXTINF:-1 tvg-id="" group-title="Daddylive",$name');
      buf.writeln(url);
    }
    return buf.toString();
  }

  /// Génère un M3U enrichi avec les URLs M3U8 trouvées.
  static String generateM3U8Playlist(DaddyliveScrapeResult scrapeResult) {
    final buf = StringBuffer('#EXTM3U\n');
    final seen = <String>{};

    // Entrées player (viewembed.ru / cdnlivetv.tv)
    for (final entry in scrapeResult.playerEntries) {
      final name = entry['name']!;
      final url = entry['url']!;
      if (seen.contains(url)) continue;
      seen.add(url);
      buf.writeln(
          '#EXTINF:-1 tvg-id="" group-title="Daddylive (Player)",$name');
      buf.writeln(url);
    }

    // M3U8 URLs directes (backup sans nom → numérotées)
    int i = 1;
    for (final url in scrapeResult.m3u8Urls) {
      if (seen.contains(url)) continue;
      seen.add(url);
      buf.writeln(
          '#EXTINF:-1 tvg-id="" group-title="Daddylive (Stream)",Stream $i');
      buf.writeln(url);
      i++;
    }

    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  //  Helpers
  // ---------------------------------------------------------------------------

  static String _normalizeName(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .trim();
  }

  static String _detectCountry(String name) {
    // Patterns: "XXX UK", "XXX France", "XXX [UK]", "XXX (USA)"
    final match = RegExp(r'\(([^)]+)\)$|\[([^\]]+)\]$|(\b[A-Z]{2,3})$')
        .firstMatch(name);
    if (match != null) {
      return (match.group(1) ?? match.group(2) ?? match.group(3) ?? '')
          .trim();
    }
    return '';
  }

  static String _detectCategory(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('sport') ||
        lower.contains('football') ||
        lower.contains('tennis') ||
        lower.contains('racing') ||
        lower.contains('golf') ||
        lower.contains('f1') ||
        lower.contains('nfl') ||
        lower.contains('nba') ||
        lower.contains('mlb') ||
        lower.contains('nhl') ||
        lower.contains('boxing') ||
        lower.contains('ufc') ||
        lower.contains('wwe') ||
        lower.contains('cricket')) {
      return 'Sport';
    }
    if (lower.contains('news')) return 'Actualités';
    if (lower.contains('movie') || lower.contains('cinema') ||
        lower.contains('film')) {
      return 'Films & Séries';
    }
    if (lower.contains('music') || lower.contains('mtv')) return 'Musique';
    if (lower.contains('kids') || lower.contains('cartoon') ||
        lower.contains('children') || lower.contains('disney')) {
      return 'Enfants';
    }
    if (lower.contains('discovery') || lower.contains('document') ||
        lower.contains('history') || lower.contains('nature')) {
      return 'Documentaires';
    }
    return 'Sport'; // Daddylive est majoritairement sport
  }

  // ---------------------------------------------------------------------------
  //  Méthode complète : fetch + scrape + convert en une seule opération
  // ---------------------------------------------------------------------------

  /// Point d'entrée principal : récupère toutes les chaînes daddylive.
  static Future<List<ChannelEntity>> fetchAllChannels() async {
    try {
      // 1) Récupère la liste API
      final apiChannels = await fetchChannels();
      if (apiChannels.isEmpty) return [];

      // 2) Scrape l'embed pour les données player
      //    Utilise l'ID de la 1ère chaîne comme "seed" (contient tous les players)
      final seedId = apiChannels.first['channel_id']?.toString() ?? '32';
      final scrapeResult = await scrapeEmbed(channelId: seedId);

      // 3) Convertit
      return toChannelEntities(apiChannels, scrapeResult);
    } catch (e) {
      debugPrint('[Daddylive] fetchAllChannels error: $e');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  //  Événements live (sports en direct)
  // ---------------------------------------------------------------------------

  /// Récupère les événements live depuis `/api/events`.
  static Future<Map<String, dynamic>> fetchLiveEvents() async {
    try {
      debugPrint('[Daddylive] Fetching live events');
      final resp = await http
          .get(Uri.parse(_apiEvents), headers: _headers)
          .timeout(_timeout);
      if (resp.statusCode != 200) return {};
      final body = resp.body.trim();
      if (!body.startsWith('[')) return {};
      final list = jsonDecode(body) as List;
      if (list.isEmpty) return {};
      return list.first as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[Daddylive] fetchLiveEvents error: $e');
      return {};
    }
  }
}
