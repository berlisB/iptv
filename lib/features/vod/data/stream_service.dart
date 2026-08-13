import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Résultat de recherche de stream pour un film/série.
class StreamResult {
  final String embedUrl;
  final String? directHlsUrl;
  final String provider;
  final Map<String, String>? headers;
  const StreamResult({
    required this.embedUrl,
    this.directHlsUrl,
    required this.provider,
    this.headers,
  });

  bool get hasDirectHls => directHlsUrl != null && directHlsUrl!.isNotEmpty;
}

/// Service gratuit pour récupérer les URLs de streaming par TMDB ID.
/// Priorité : HLS direct (media_kit) > embed (WebView).
class StreamService {
  StreamService._();

  /// Récupère un stream pour un film par TMDB ID.
  static Future<StreamResult?> getMovieStream(int tmdbId) async {
    debugPrint('[Stream] Getting stream for movie TMDB:$tmdbId');

    // Provider 1 : VidCore /api/sources (HLS direct via proxy)
    final vc = await _vidcoreHlsMovie(tmdbId);
    if (vc != null && vc.hasDirectHls) {
      debugPrint('[Stream] ✅ VidCore HLS direct');
      return vc;
    }

    // Provider 2 : SuperEmbed (fallback WebView)
    debugPrint('[Stream] Using SuperEmbed fallback');
    return _superembedMovie(tmdbId);
  }

  /// Récupère un stream pour un épisode de série.
  static Future<StreamResult?> getTvStream(int tmdbId,
      {int season = 1, int episode = 1}) async {
    debugPrint('[Stream] Getting stream for TV TMDB:$tmdbId S${season}E$episode');

    final vc = await _vidcoreHlsTv(tmdbId, season: season, episode: episode);
    if (vc != null && vc.hasDirectHls) {
      debugPrint('[Stream] ✅ VidCore HLS direct');
      return vc;
    }

    debugPrint('[Stream] Using SuperEmbed fallback');
    return _superembedTv(tmdbId, season: season, episode: episode);
  }

  // --- VidCore /api/sources (HLS direct via proxy) ---

  static Future<StreamResult?> _vidcoreHlsMovie(int tmdbId) async {
    try {
      final url = 'https://vidcore.org/api/sources?id=$tmdbId&type=movie';
      final resp = await http
          .get(Uri.parse(url), headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Referer': 'https://vidcore.org/',
            'Origin': 'https://vidcore.org',
          })
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        return _parseVidcoreSources(resp.body, tmdbId, 'movie');
      }
    } catch (e) {
      debugPrint('[Stream] VidCore HLS movie error: $e');
    }
    return null;
  }

  static Future<StreamResult?> _vidcoreHlsTv(int tmdbId,
      {int season = 1, int episode = 1}) async {
    try {
      final url =
          'https://vidcore.org/api/sources?id=$tmdbId&type=tv&season=$season&episode=$episode';
      final resp = await http
          .get(Uri.parse(url), headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Referer': 'https://vidcore.org/',
            'Origin': 'https://vidcore.org',
          })
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        return _parseVidcoreSources(resp.body, tmdbId, 'tv');
      }
    } catch (e) {
      debugPrint('[Stream] VidCore HLS tv error: $e');
    }
    return null;
  }

  /// Parse la réponse JSON de /api/sources pour extraire l'URL HLS.
  static StreamResult? _parseVidcoreSources(
      String body, int tmdbId, String type) {
    try {
      final data = jsonDecode(body);
      final sources = data['sources'] as List?;
      if (sources == null || sources.isEmpty) return null;

      for (final source in sources) {
        if (source is! Map<String, dynamic>) continue;
        final sourceData = source['data'] as Map<String, dynamic>?;
        if (sourceData == null) continue;

        final innerSources = sourceData['sources'] as List?;
        if (innerSources == null || innerSources.isEmpty) continue;

        for (final s in innerSources) {
          if (s is! Map<String, dynamic>) continue;
          final streamUrl = s['url'] as String?;
          if (streamUrl == null || streamUrl.isEmpty) continue;

          final label = source['label'] as String? ?? 'unknown';
          debugPrint('[Stream] VidCore source: $label');

          // Try to extract the real upstream URL from the proxy URL
          final parsed = _extractUpstreamFromProxy(streamUrl);
          if (parsed != null) {
            debugPrint('[Stream] ✅ Extracted upstream: ${parsed.url.substring(0, 80)}...');
            return StreamResult(
              embedUrl: 'https://vidcore.org/embed/$type/$tmdbId',
              directHlsUrl: parsed.url,
              provider: 'vidcore',
              headers: parsed.headers,
            );
          }

          // Fallback: use the proxy URL as-is
          debugPrint('[Stream] ✅ Using proxy URL directly');
          return StreamResult(
            embedUrl: 'https://vidcore.org/embed/$type/$tmdbId',
            directHlsUrl: streamUrl,
            provider: 'vidcore',
            headers: {
              'Referer': 'https://vidcore.org/',
              'Origin': 'https://vidcore.org',
            },
          );
        }
      }
    } catch (e) {
      debugPrint('[Stream] VidCore parse error: $e');
    }
    return null;
  }

  /// Extrait l'URL upstream réelle et les headers depuis une URL proxy VidCore.
  /// Format: .../m3u8-proxy.m3u8?url=<upstream>&headers=<json_headers>
  static _UpstreamInfo? _extractUpstreamFromProxy(String proxyUrl) {
    try {
      final uri = Uri.parse(proxyUrl);
      final upstreamUrl = uri.queryParameters['url'];
      final headersJson = uri.queryParameters['headers'];

      if (upstreamUrl == null || upstreamUrl.isEmpty) return null;

      final headers = <String, String>{};
      if (headersJson != null && headersJson.isNotEmpty) {
        final decoded = jsonDecode(Uri.decodeFull(headersJson));
        if (decoded is Map<String, dynamic>) {
          for (final entry in decoded.entries) {
            headers[entry.key] = entry.value.toString();
          }
        }
      }

      return _UpstreamInfo(upstreamUrl, headers);
    } catch (e) {
      debugPrint('[Stream] Proxy parse error: $e');
      return null;
    }
  }

  // --- SuperEmbed (fallback WebView) ---

  static StreamResult _superembedMovie(int tmdbId) {
    return StreamResult(
      embedUrl: 'https://multiembed.mov/?video_id=$tmdbId&tmdb=1',
      provider: 'superembed',
    );
  }

  static StreamResult _superembedTv(int tmdbId,
      {int season = 1, int episode = 1}) {
    return StreamResult(
      embedUrl:
          'https://multiembed.mov/?video_id=$tmdbId&tmdb=1&s=$season&e=$episode',
      provider: 'superembed',
    );
  }
}

class _UpstreamInfo {
  final String url;
  final Map<String, String> headers;
  _UpstreamInfo(this.url, this.headers);
}
