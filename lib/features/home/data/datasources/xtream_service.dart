import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:iptv/features/home/domain/entities/channel_entity.dart';

/// Connecte un abonnement IPTV au format Xtream Codes (host + user + password)
/// et convertit ses chaînes live en ChannelEntity (avec failover .m3u8 → .ts).
class XtreamService {
  XtreamService._();

  /// Normalise le host saisi (ajoute http:// si absent, retire le slash final).
  static String normalizeHost(String host) {
    var h = host.trim();
    if (!h.startsWith('http://') && !h.startsWith('https://')) h = 'http://$h';
    if (h.endsWith('/')) h = h.substring(0, h.length - 1);
    return h;
  }

  static Uri _api(String host, String u, String p, String action) =>
      Uri.parse('$host/player_api.php?username=$u&password=$p&action=$action');

  /// Vérifie les identifiants. Renvoie true si le compte est actif.
  static Future<bool> validate(String host, String u, String p) async {
    try {
      final url = Uri.parse('$host/player_api.php?username=$u&password=$p');
      final r = await http.get(url).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return false;
      final json = jsonDecode(r.body) as Map<String, dynamic>;
      final info = json['user_info'] as Map<String, dynamic>?;
      return info != null && '${info['auth']}' == '1';
    } catch (e) {
      debugPrint('[Xtream] validate échec: $e');
      return false;
    }
  }

  /// Récupère toutes les chaînes live de l'abonnement.
  static Future<List<ChannelEntity>> fetchLiveChannels({
    required String host,
    required String username,
    required String password,
  }) async {
    final result = <ChannelEntity>[];
    try {
      // 1) Catégories : id → nom (pour le group-title).
      final catResp = await http
          .get(_api(host, username, password, 'get_live_categories'))
          .timeout(const Duration(seconds: 25));
      final categories = <String, String>{};
      if (catResp.statusCode == 200) {
        for (final c in jsonDecode(catResp.body) as List) {
          categories['${c['category_id']}'] = '${c['category_name']}';
        }
      }

      // 2) Flux live.
      final resp = await http
          .get(_api(host, username, password, 'get_live_streams'))
          .timeout(const Duration(seconds: 35));
      if (resp.statusCode != 200) return result;

      for (final s in jsonDecode(resp.body) as List) {
        final id = '${s['stream_id']}';
        if (id.isEmpty) continue;
        final group = categories['${s['category_id']}'] ?? 'Xtream';
        final base = '$host/live/$username/$password/$id';

        result.add(ChannelEntity(
          id: 'xtream_$id',
          name: '${s['name']}'.trim(),
          url: '$base.m3u8',
          backupUrls: ['$base.ts'], // failover si le panel ne sert pas le HLS
          logoUrl: '${s['stream_icon'] ?? ''}',
          group: group,
          tvgId: '${s['epg_channel_id'] ?? ''}',
          mediaType: MediaType.livestream,
        ));
      }
      debugPrint('[Xtream] ${result.length} chaînes chargées');
    } catch (e) {
      debugPrint('[Xtream] fetch échec: $e');
    }
    return result;
  }
}
