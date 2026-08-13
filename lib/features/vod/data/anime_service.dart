import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:iptv/features/vod/domain/anime_entity.dart';

/// Service pour chercher et lire des animes depuis animes-sama.fr.
class AnimeService {
  AnimeService._();

  static const _baseUrl = 'https://animes-sama.fr';

  /// Recherche d'animes.
  static Future<List<AnimeEntity>> search(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final resp = await http
          .post(
            Uri.parse('$_baseUrl/ajax/search.php'),
            headers: {
              'X-Requested-With': 'XMLHttpRequest',
              'Referer': _baseUrl,
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: 'query=${Uri.encodeComponent(query)}',
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) return [];
      return _parseSearchResults(resp.body);
    } catch (e) {
      debugPrint('[Anime] Search error: $e');
      return [];
    }
  }

  /// Récupère les saisons disponibles pour un anime.
  static Future<List<Map<String, String>>> getSeasons(String slug) async {
    try {
      final url = '$_baseUrl/catalogue/$slug';
      final resp = await http
          .get(Uri.parse(url), headers: {'Referer': _baseUrl})
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) return [];
      return _parseSeasons(resp.body, slug);
    } catch (e) {
      debugPrint('[Anime] getSeasons error: $e');
      return [];
    }
  }

  /// Récupère le nombre d'épisodes et les embed URLs pour une saison donnée.
  static Future<List<AnimeEpisode>> getEpisodes(
    String slug, {
    String season = 'saison1',
    String lang = 'vostfr',
  }) async {
    try {
      final url = '$_baseUrl/catalogue/$slug/$season/$lang';
      debugPrint('[Anime] Fetching: $url');
      final resp = await http
          .get(Uri.parse(url), headers: {'Referer': _baseUrl})
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) return [];
      return _parseEpisodes(resp.body);
    } catch (e) {
      debugPrint('[Anime] getEpisodes error: $e');
      return [];
    }
  }

  /// Extrait l'URL m3u8 depuis une page d'embed.
  static Future<String?> extractStreamUrl(String embedUrl, String provider) async {
    if (provider == 'vidmoly') return _extractVidmolyM3u8(embedUrl);
    if (provider == 'sibnet') return _extractSibnetMp4(embedUrl);
    return null;
  }

  static Future<String?> _extractVidmolyM3u8(String embedUrl) async {
    final client = http.Client();
    try {
      // VidMoly returns a JS redirect first → follow it manually
      final firstResp = await client
          .get(Uri.parse(embedUrl), headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Referer': 'https://vidmoly.net/',
            'Sec-Fetch-Dest': 'iframe',
          })
          .timeout(const Duration(seconds: 10));

      if (firstResp.statusCode != 200) return null;

      // Extract redirect URL from JS: window.location.replace('...')
      final redirectMatch = RegExp(
        r"window\.location\.replace\(['\x22]([^'\x22]+)['\x22]\)",
      ).firstMatch(firstResp.body);

      if (redirectMatch == null) return null;
      final redirectUrl = redirectMatch.group(1)!;

      // Follow the redirect
      final secondResp = await client
          .get(Uri.parse(redirectUrl), headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Referer': embedUrl,
          })
          .timeout(const Duration(seconds: 10));

      if (secondResp.statusCode != 200) return null;
      final body = secondResp.body;

      final patterns = [
        RegExp(r"""file\s*:\s*["']([^"']*\.m3u8[^"']*)["']"""),
        RegExp(r"""sources\s*:\s*\[\{[^}]*file\s*:\s*["']([^"']*\.m3u8[^"']*)["']"""),
        RegExp(r"""(https?://[^"'\s]+\.m3u8[^"'\s]*)"""),
      ];

      for (final pattern in patterns) {
        final match = pattern.firstMatch(body);
        if (match != null) {
          var m3u8Url = match.group(1)!;
          if (m3u8Url.startsWith('//')) m3u8Url = 'https:$m3u8Url';
          if (m3u8Url.startsWith('http')) {
            debugPrint('[Anime] ✅ VidMoly m3u8 found after redirect');
            return m3u8Url;
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('[Anime] VidMoly extract error: $e');
      return null;
    } finally {
      client.close();
    }
  }

  static Future<String?> _extractSibnetMp4(String embedUrl) async {
    try {
      final resp = await http
          .get(Uri.parse(embedUrl), headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          })
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) return null;
      final body = resp.body;
      final pattern = RegExp(r"""player\.src\(\[\{src\s*:\s*["']([^"']+\.mp4)["']""");
      final match = pattern.firstMatch(body);
      if (match != null) {
        var mp4Url = match.group(1)!;
        if (mp4Url.startsWith('/')) mp4Url = 'https://video.sibnet.ru$mp4Url';
        debugPrint('[Anime] ✅ SibNet MP4 found');
        return mp4Url;
      }
      return null;
    } catch (e) {
      debugPrint('[Anime] SibNet extract error: $e');
      return null;
    }
  }

  static List<AnimeEntity> _parseSearchResults(String html) {
    final results = <AnimeEntity>[];
    final pattern = RegExp(
      r'<a\s+href="/catalogue/([^"]+)"[^>]*>.*?<h3[^>]*>([^<]+)</h3>',
      dotAll: true,
    );
    for (final match in pattern.allMatches(html)) {
      final slug = match.group(1)!;
      final title = match.group(2)!.trim();
      // Extraire l'image
      final imgPattern = RegExp(r'src="([^"]+)"');
      final imgMatch = imgPattern.firstMatch(match.group(0)!);
      final imageUrl = imgMatch?.group(1) ?? '';
      results.add(AnimeEntity(slug: slug, title: title, imageUrl: imageUrl));
    }
    final seen = <String>{};
    return results.where((a) => seen.add(a.slug)).toList();
  }

  /// Parse les saisons depuis la page catalogue.
  static List<Map<String, String>> _parseSeasons(String html, String slug) {
    final seasons = <Map<String, String>>[];
    // Pattern: href="/catalogue/{slug}/saison{N}/{lang}"
    final pattern = RegExp(
      r'href="/catalogue/' + RegExp.escape(slug) + r'/(saison\d+)/([a-z]+)"',
    );
    final seen = <String>{};
    for (final match in pattern.allMatches(html)) {
      final season = match.group(1)!;
      final lang = match.group(2)!;
      final key = '$season/$lang';
      if (seen.add(key)) {
        seasons.add({'season': season, 'lang': lang});
      }
    }
    return seasons;
  }

  /// Parse les épisodes depuis la page anime (tableau JS eps1, eps2...).
  static List<AnimeEpisode> _parseEpisodes(String html) {
    final episodes = <AnimeEpisode>[];

    // Parser toutes les lignes var epsN = [...]
    final epsPattern = RegExp(
      r'var\s+eps(\d+)\s*=\s*\[(.*?)\];',
      dotAll: true,
    );

    // Collecter tous les lecteurs et leurs URLs
    final lecteurs = <int, List<String>>{};
    for (final match in epsPattern.allMatches(html)) {
      final lecteur = int.tryParse(match.group(1)!) ?? 999;
      final urlsRaw = match.group(2)!;
      final urlPattern = RegExp(r'"(https?://[^"]+)"');
      final urls = urlPattern
          .allMatches(urlsRaw)
          .map((m) => m.group(1)!)
          .toList();
      if (urls.isNotEmpty) {
        lecteurs[lecteur] = urls;
      }
    }

    if (lecteurs.isEmpty) return episodes;

    // Trouver le meilleur lecteur (VidMoly > SendVid > SibNet)
    int bestLecteur = -1;
    for (final entry in lecteurs.entries) {
      for (final url in entry.value) {
        if (url.contains('vidmoly')) {
          bestLecteur = entry.key;
          break;
        }
      }
      if (bestLecteur >= 0) break;
    }
    if (bestLecteur < 0) {
      // Fallback: premier lecteur disponible
      bestLecteur = lecteurs.keys.first;
    }

    final urls = lecteurs[bestLecteur]!;
    if (urls.isEmpty) return episodes;

    // Déterminer le provider
    String provider = 'unknown';
    if (urls.first.contains('vidmoly')) provider = 'vidmoly';
    else if (urls.first.contains('sibnet')) provider = 'sibnet';
    else if (urls.first.contains('sendvid')) provider = 'sendvid';

    // Créer un épisode par URL
    for (var i = 0; i < urls.length; i++) {
      episodes.add(AnimeEpisode(
        number: i + 1,
        embedUrl: urls[i],
        provider: provider,
      ));
    }

    debugPrint('[Anime] Parsed ${episodes.length} episodes (lecteur $bestLecteur)');
    return episodes;
  }
}
