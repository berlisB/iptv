import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';
import 'package:iptv/features/epg/domain/epg_programme.dart';

/// Télécharge et parse un guide XMLTV en streaming (sans charger tout le fichier).
class EpgService {
  EpgService._();

  /// Source par défaut : guide France (epgshare01), gzippé.
  static const defaultUrl =
      'https://epgshare01.online/epgshare01/epg_ripper_FR1.xml.gz';

  /// Parse le guide et ne conserve que les programmes des chaînes voulues,
  /// dans une fenêtre utile (passé proche → +12h). Limite la mémoire.
  static Future<Map<String, List<EpgProgramme>>> fetch({
    required Set<String> wantedIds,
    String url = defaultUrl,
    DateTime? now,
  }) async {
    final result = <String, List<EpgProgramme>>{};
    if (wantedIds.isEmpty) return result;

    final ref = now ?? DateTime.now();
    final from = ref.subtract(const Duration(hours: 3));
    final until = ref.add(const Duration(hours: 12));

    try {
      final client = http.Client();
      final resp =
          await client.send(http.Request('GET', Uri.parse(url))).timeout(
                const Duration(seconds: 40),
              );

      Stream<List<int>> bytes = resp.stream;
      if (url.endsWith('.gz')) bytes = bytes.transform(gzip.decoder);

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
          if (channel == null || !wantedIds.contains(channel)) continue;

          final start = _parseXmltvDate(el.getAttribute('start'));
          final stop = _parseXmltvDate(el.getAttribute('stop'));
          if (start == null || stop == null) continue;
          if (stop.isBefore(from) || start.isAfter(until)) continue;

          final title = el.getElement('title')?.innerText.trim() ?? '';
          if (title.isEmpty) continue;

          (result[channel] ??= []).add(EpgProgramme(
            channelId: channel,
            start: start,
            stop: stop,
            title: title,
          ));
        }
      }

      for (final list in result.values) {
        list.sort((a, b) => a.start.compareTo(b.start));
      }
      client.close();
      debugPrint('[EPG] ${result.length} chaînes avec guide chargé');
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
