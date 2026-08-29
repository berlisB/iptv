import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:iptv/core/services/disk_cache.dart';
import 'package:iptv/features/home/domain/entities/channel_entity.dart';

/// Catalogue v3 : l'artefact riche généré toutes les 6 h par la CI
/// (tools/healthcheck.py → catalog.json). ~5000 chaînes vérifiées vivantes,
/// dédupliquées par identité stable, avec URLs de secours et catégories.
///
/// Chaîne de chargement :
///   1. cache disque frais (< 6 h) — zéro réseau au démarrage courant ;
///   2. Worker Cloudflare (si configuré) puis GitHub raw ;
///   3. cache disque même périmé (réseau mort) ;
///   4. asset embarqué (première installation hors ligne).
class CatalogV3Source {
  CatalogV3Source._();

  /// URL du Worker (worker/README.md) ; vide = on saute l'étape Worker.
  /// Renseignable à la compilation : --dart-define=WORKER_BASE_URL=https://…
  static const String _workerBase =
      String.fromEnvironment('WORKER_BASE_URL', defaultValue: '');

  static const String _rawUrl =
      'https://raw.githubusercontent.com/berlisB/iptv/main/catalog.json';
  static const String _asset = 'assets/catalog/catalog.json';
  static const String _cacheKey = 'catalog_v3.json';
  static const Duration _ttl = Duration(hours: 6);

  static Future<List<ChannelEntity>> load() async {
    final fresh = await DiskCache.readString(_cacheKey, maxAge: _ttl);
    if (fresh != null) {
      final channels = await _parse(fresh);
      if (channels.isNotEmpty) {
        debugPrint('[CatalogV3] cache disque frais (${channels.length})');
        return channels;
      }
    }

    final remote = await _fetchRemote();
    if (remote != null) {
      final channels = await _parse(remote);
      if (channels.isNotEmpty) {
        await DiskCache.writeString(_cacheKey, remote);
        debugPrint('[CatalogV3] réseau OK (${channels.length})');
        return channels;
      }
    }

    final stale = await DiskCache.readString(_cacheKey);
    if (stale != null) {
      final channels = await _parse(stale);
      if (channels.isNotEmpty) {
        debugPrint('[CatalogV3] réseau KO → cache périmé (${channels.length})');
        return channels;
      }
    }

    try {
      final channels = await _parse(await rootBundle.loadString(_asset));
      debugPrint('[CatalogV3] repli asset embarqué (${channels.length})');
      return channels;
    } catch (e) {
      debugPrint('[CatalogV3] asset indisponible: $e');
      return const [];
    }
  }

  static Future<String?> _fetchRemote() async {
    if (_workerBase.isNotEmpty) {
      final viaWorker = await _get('$_workerBase/catalog.json',
          timeout: const Duration(seconds: 5));
      if (viaWorker != null) return viaWorker;
    }
    return _get(_rawUrl, timeout: const Duration(seconds: 12));
  }

  static Future<String?> _get(String url, {required Duration timeout}) async {
    try {
      final r = await http.get(Uri.parse(url)).timeout(timeout);
      if (r.statusCode == 200 && r.body.length > 2) return r.body;
      debugPrint('[CatalogV3] $url → HTTP ${r.statusCode}');
    } catch (e) {
      debugPrint('[CatalogV3] $url → $e');
    }
    return null;
  }

  /// Parse + mapping dans un isolate (~1,5 Mo de JSON, éviter le jank).
  static Future<List<ChannelEntity>> _parse(String body) async {
    try {
      return await compute(_decodeCatalog, body);
    } catch (e) {
      debugPrint('[CatalogV3] parse: $e');
      return const [];
    }
  }
}

List<ChannelEntity> _decodeCatalog(String body) {
  final root = jsonDecode(body);
  if (root is! Map || root['version'] != 3) return const [];
  final generatedAt = DateTime.tryParse(root['generatedAt']?.toString() ?? '');
  final list = root['channels'];
  if (list is! List) return const [];

  return [
    for (final j in list.whereType<Map<String, dynamic>>())
      _channelFromV3(j, generatedAt),
  ];
}

ChannelEntity _channelFromV3(Map<String, dynamic> j, DateTime? checkedAt) {
  final urls = (j['urls'] as List?)?.cast<String>() ?? const [];
  final category = (j['category'] as String?) ?? '';
  final curated = j['curated'] == true;
  final provider = (j['provider'] as String?) ?? 'other';
  return ChannelEntity(
    id: (j['id'] as String?) ?? '',
    name: (j['name'] as String?) ?? '',
    url: urls.isNotEmpty ? urls.first : '',
    backupUrls: urls.length > 1 ? urls.sublist(1) : const [],
    logoUrl: (j['logo'] as String?) ?? '',
    group: category.isEmpty ? 'Autres' : category,
    category: category,
    language: (j['language'] as String?) ?? '',
    country: (j['country'] as String?) ?? '',
    tvgId: (j['tvgId'] as String?) ?? '',
    priority: curated ? ((j['priority'] as num?)?.toInt() ?? 1) : 3,
    sourceType: curated || provider == 'official'
        ? SourceType.officialOrPublic
        : SourceType.communityVerified,
    // Vérifié vivant par le pipeline il y a < 6 h.
    status: ChannelStatus.online,
    lastCheckedAt: checkedAt,
  );
}
