import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:iptv/core/services/disk_cache.dart';
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';
import 'package:iptv/features/epg/domain/epg_programme.dart';
import 'package:iptv/features/epg/data/epg_id_mapping.dart';

/// Télécharge et parse des guides XMLTV en streaming (sans charger tout le
/// fichier). Multi-packs : guide FR (epgshare01) + guides FAST (i.mjh.nz,
/// mêmes ids que les tvg-id des playlists Pluto/Samsung).
class EpgService {
  EpgService._();

  /// URL du Worker (cache edge) ; vide = accès direct aux sources.
  static const String _workerBase =
      String.fromEnvironment('WORKER_BASE_URL', defaultValue: '');

  /// Packs disponibles — mêmes clés que la whitelist du Worker.
  static const Map<String, String> packUrls = {
    'fr1': 'https://epgshare01.online/epgshare01/epg_ripper_FR1.xml.gz',
    'pluto-fr': 'https://i.mjh.nz/PlutoTV/fr.xml.gz',
    'pluto-us': 'https://i.mjh.nz/PlutoTV/us.xml.gz',
    'samsung-fr': 'https://i.mjh.nz/SamsungTVPlus/fr.xml.gz',
    'samsung-us': 'https://i.mjh.nz/SamsungTVPlus/us.xml.gz',
  };

  static const Duration _cacheTtl = Duration(hours: 12);

  /// Charge plusieurs packs et fusionne leurs programmes par chaîne.
  static Future<Map<String, List<EpgProgramme>>> fetchPacks({
    required Set<String> wantedIds,
    required List<String> packs,
    DateTime? now,
  }) async {
    final result = <String, List<EpgProgramme>>{};
    for (final pack in packs) {
      final partial = await fetch(wantedIds: wantedIds, pack: pack, now: now);
      partial.forEach((id, programmes) {
        (result[id] ??= []).addAll(programmes);
      });
    }
    for (final list in result.values) {
      list.sort((a, b) => a.start.compareTo(b.start));
    }
    return result;
  }

  /// Le .gz brut d'un pack : cache disque frais → Worker → direct → cache
  /// périmé. Le gz est 5-10× plus petit que le XML, on ne stocke que lui.
  static Future<Uint8List?> _loadPackBytes(String pack) async {
    final cacheKey = 'epg_$pack.gz';
    final fresh = await DiskCache.readBytes(cacheKey, maxAge: _cacheTtl);
    if (fresh != null) {
      debugPrint('[EPG] cache disque frais: $pack');
      return fresh;
    }
    final urls = [
      if (_workerBase.isNotEmpty) '$_workerBase/epg/$pack.xml.gz',
      packUrls[pack]!,
    ];
    for (final url in urls) {
      try {
        final r = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 40));
        if (r.statusCode == 200 && r.bodyBytes.length > 100) {
          await DiskCache.writeBytes(cacheKey, r.bodyBytes);
          return r.bodyBytes;
        }
        debugPrint('[EPG] $url → HTTP ${r.statusCode}');
      } catch (e) {
        debugPrint('[EPG] $url → $e');
      }
    }
    return DiskCache.readBytes(cacheKey); // périmé, mieux que rien
  }

  /// Parse le guide et ne conserve que les programmes des chaînes voulues,
  /// dans une fenêtre utile (passé proche → +12h). Limite la mémoire.
  static Future<Map<String, List<EpgProgramme>>> fetch({
    required Set<String> wantedIds,
    String pack = 'fr1',
    DateTime? now,
  }) async {
    final result = <String, List<EpgProgramme>>{};
    if (wantedIds.isEmpty || !packUrls.containsKey(pack)) return result;

    final ref = now ?? DateTime.now();
    final from = ref.subtract(const Duration(hours: 3));
    final until = ref.add(const Duration(hours: 12));

    // Convertir les tvgId du catalogue en channel id XMLTV
    final epgIds = EpgIdMapping.toEpgIds(wantedIds);
    // Map epgId → catalogId pour retrouver nos IDs après parsing
    final epgToCatalog = <String, String>{};
    for (final catalogId in wantedIds) {
      final epgId = EpgIdMapping.toEpgId(catalogId);
      epgToCatalog[epgId] = catalogId;
    }

    debugPrint('[EPG] $pack: recherche de ${epgIds.length} chaînes');

    try {
      final gz = await _loadPackBytes(pack);
      if (gz == null) return result;

      final bytes = Stream<List<int>>.value(gz).transform(gzip.decoder);

      // Parsing événementiel : on ne garde que les <programme> pertinents.
      final events = bytes
          .transform(utf8.decoder)
          .toXmlEvents()
          .normalizeEvents()
          .selectSubtreeEvents((e) => e.localName == 'programme')
          .toXmlNodes();

      await for (final nodes in events) {
        for (final node in nodes) {
          if (node is! XmlElement) continue;
          final el = node;
          final channel = el.getAttribute('channel');
          if (channel == null || !epgIds.contains(channel)) continue;

          // Retrouver le tvgId du catalogue
          final catalogId = epgToCatalog[channel] ?? channel;

          final start = _parseXmltvDate(el.getAttribute('start'));
          final stop = _parseXmltvDate(el.getAttribute('stop'));
          if (start == null || stop == null) continue;
          if (stop.isBefore(from) || start.isAfter(until)) continue;

          final title = el.getElement('title')?.innerText.trim() ?? '';
          if (title.isEmpty) continue;

          (result[catalogId] ??= []).add(EpgProgramme(
            channelId: catalogId,
            start: start,
            stop: stop,
            title: title,
          ));
        }
      }

      for (final list in result.values) {
        list.sort((a, b) => a.start.compareTo(b.start));
      }
      debugPrint('[EPG] $pack: ${result.length} chaînes avec guide');
    } catch (e) {
      debugPrint('[EPG] échec du chargement: $e');
    }
    return result;
  }

  /// Parse une date XMLTV "20260614120000 +0200" → DateTime UTC.
  static DateTime? _parseXmltvDate(String? raw) {
    if (raw == null || raw.length < 14) return null;
    try {
      final y = int.parse(raw.substring(0, 4));
      final mo = int.parse(raw.substring(4, 6));
      final d = int.parse(raw.substring(6, 8));
      final h = int.parse(raw.substring(8, 10));
      final mi = int.parse(raw.substring(10, 12));
      final s = int.parse(raw.substring(12, 14));
      var dt = DateTime.utc(y, mo, d, h, mi, s);

      // Décalage horaire optionnel " +0200".
      final tz = raw.substring(14).trim();
      if (tz.length >= 5) {
        final sign = tz[0] == '-' ? 1 : -1; // on ramène en UTC
        final offH = int.parse(tz.substring(1, 3));
        final offM = int.parse(tz.substring(3, 5));
        dt = dt.add(Duration(hours: sign * offH, minutes: sign * offM));
      }
      return dt;
    } catch (_) {
      return null;
    }
  }
}
