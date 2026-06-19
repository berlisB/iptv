import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:iptv/features/home/domain/entities/channel_entity.dart';

/// Résultat d'un probe réseau d'un flux.
enum ProbeOutcome { ok, timeout, forbidden, notFound, error }

/// Teste si une URL de flux répond, sans télécharger tout le manifeste.
///
/// On envoie un GET avec `Range: bytes=0-2047` (les serveurs HLS répondent en
/// général 200/206) et on relâche la connexion aussitôt l'en-tête reçu. Ça
/// suffit à distinguer vivant / 403 / 404 / timeout / erreur réseau.
class StreamValidator {
  StreamValidator({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _defaultTimeout = Duration(seconds: 8);

  Future<ProbeOutcome> probe(
    String url, {
    Map<String, String>? headers,
    Duration timeout = _defaultTimeout,
  }) async {
    http.StreamedResponse? res;
    try {
      final req = http.Request('GET', Uri.parse(url));
      req.headers['Range'] = 'bytes=0-2047';
      req.headers['User-Agent'] = 'Mozilla/5.0';
      if (headers != null) req.headers.addAll(headers);

      res = await _client.send(req).timeout(timeout);
      final code = res.statusCode;
      // On draine en arrière-plan pour libérer la socket sans bloquer.
      unawaited(res.stream.drain<void>().catchError((_) {}));

      if (code == 403) return ProbeOutcome.forbidden;
      if (code == 404 || code == 410) return ProbeOutcome.notFound;
      if (code >= 200 && code < 400) return ProbeOutcome.ok;
      return ProbeOutcome.error;
    } on TimeoutException {
      return ProbeOutcome.timeout;
    } catch (e) {
      debugPrint('[Validator] $url → $e');
      return ProbeOutcome.error;
    }
  }

  /// Probe la chaîne (URL principale puis secours) et renvoie le statut déduit.
  /// Le 1er flux vivant suffit à considérer la chaîne en ligne.
  Future<ChannelStatus> validateChannel(ChannelEntity channel) async {
    for (final url in channel.allUrls) {
      final outcome = await probe(url, headers: _headersFor(channel));
      if (outcome == ProbeOutcome.ok) return ChannelStatus.online;
    }
    return ChannelStatus.offline;
  }

  Map<String, String>? _headersFor(ChannelEntity c) {
    if (!c.httpHeaders.hasHeaders) return null;
    return {
      if (c.httpHeaders.referrer != null) 'Referer': c.httpHeaders.referrer!,
      if (c.httpHeaders.httpOrigin != null) 'Origin': c.httpHeaders.httpOrigin!,
    };
  }
}
