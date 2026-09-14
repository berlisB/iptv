/// Indexation du canal Telegram : parcourt l'historique et en extrait les
/// fichiers vidéo publiés.
///
/// L'indexation est faite sur l'appareil, pas en CI, parce qu'elle n'a besoin
/// d'aucun secret : TDLib est déjà authentifié avec le compte de
/// l'utilisateur. Le résultat est mis en cache sur disque, donc le parcours
/// complet n'a lieu qu'au premier lancement — ensuite, seuls les messages plus
/// récents que le dernier indexé sont récupérés.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:iptv/core/services/disk_cache.dart';
import 'package:iptv/features/telegram/data/telegram_service.dart';
import 'package:iptv/features/telegram/domain/telegram_media.dart';

class TelegramChannelSource {
  TelegramChannelSource._();

  /// Messages demandés par appel. TDLib plafonne à 100, et une valeur élevée
  /// réduit le nombre d'allers-retours sur un canal de plusieurs milliers de
  /// fichiers.
  static const _pageSize = 100;

  /// Garde-fou : un canal très ancien pourrait faire boucler l'indexation
  /// longtemps. Au-delà, on s'arrête et on reprendra au prochain lancement.
  static const _maxMessages = 5000;

  static String _cacheKey(int chatId) => 'tg_index_$chatId';

  /// Charge l'index depuis le cache disque, sans réseau.
  static Future<List<TelegramMedia>> loadCached(int chatId) async {
    final raw = await DiskCache.readString(_cacheKey(chatId));
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => _fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } catch (e) {
      debugPrint('[TG] index en cache illisible: $e');
      return [];
    }
  }

  /// Parcourt l'historique du canal et retourne les vidéos trouvées, les plus
  /// récentes d'abord.
  ///
  /// [knownNewestId] permet l'indexation incrémentale : si fourni, le parcours
  /// s'arrête dès qu'on retombe sur un message déjà connu.
  ///
  /// [onProgress] est appelé au fil des pages, pour que l'UI affiche l'avancée
  /// plutôt qu'un spinner muet sur un canal volumineux.
  static Future<List<TelegramMedia>> fetchHistory(
    int chatId, {
    int knownNewestId = 0,
    void Function(int found)? onProgress,
  }) async {
    final service = TelegramService.instance;
    final found = <TelegramMedia>[];
    var fromMessageId = 0; // 0 = depuis le message le plus récent
    var scanned = 0;

    while (scanned < _maxMessages) {
      final response = await service.request({
        '@type': 'getChatHistory',
        'chat_id': chatId,
        'from_message_id': fromMessageId,
        'offset': 0,
        'limit': _pageSize,
        // false = autorise TDLib à interroger le serveur, pas seulement son
        // cache local, sinon le premier parcours revient quasiment vide.
        'only_local': false,
      });

      final messages = (response?['messages'] as List?) ?? const [];
      if (messages.isEmpty) break;

      var reachedKnown = false;
      for (final raw in messages) {
        final message = raw as Map<String, dynamic>;
        final id = message['id'] as int?;
        if (id == null) continue;
        fromMessageId = id;
        scanned++;

        if (knownNewestId > 0 && id <= knownNewestId) {
          reachedKnown = true;
          break;
        }
        final media = _extractMedia(message);
        if (media != null) found.add(media);
      }

      onProgress?.call(found.length);
      if (reachedKnown) break;
      // Une page plus courte que demandée signifie la fin de l'historique.
      if (messages.length < _pageSize) break;
    }

    debugPrint('[TG] indexation: $scanned messages lus, ${found.length} vidéos');
    return found;
  }

  /// Indexation complète avec cache : renvoie l'index à jour et le persiste.
  static Future<List<TelegramMedia>> refresh(
    int chatId, {
    void Function(int found)? onProgress,
  }) async {
    final cached = await loadCached(chatId);
    final newestKnown = cached.isEmpty
        ? 0
        : cached.map((m) => m.messageId).reduce((a, b) => a > b ? a : b);

    final fresh = await fetchHistory(
      chatId,
      knownNewestId: newestKnown,
      onProgress: onProgress,
    );

    // Fusion : les nouveaux passent devant, la dédup par messageId protège
    // d'un recouvrement entre les deux parcours.
    final byId = <int, TelegramMedia>{};
    for (final m in [...fresh, ...cached]) {
      byId.putIfAbsent(m.messageId, () => m);
    }
    final merged = byId.values.toList()
      ..sort((a, b) => b.messageId.compareTo(a.messageId));

    await DiskCache.writeString(
      _cacheKey(chatId),
      jsonEncode(merged.map(_toJson).toList()),
    );
    return merged;
  }

  /// Vide l'index en cache, pour forcer un parcours complet.
  static Future<void> clearCache(int chatId) =>
      DiskCache.writeString(_cacheKey(chatId), '[]');

  // -------------------------------------------------------------------------
  // Extraction
  // -------------------------------------------------------------------------

  /// Un message → une vidéo, ou null si le message n'en contient pas.
  ///
  /// Deux formes portent un film : `messageVideo` (Telegram a reconnu une
  /// vidéo) et `messageDocument` (fichier envoyé sans compression, cas le plus
  /// courant pour un film, justement pour préserver la qualité).
  static TelegramMedia? _extractMedia(Map<String, dynamic> message) {
    final content = message['content'] as Map<String, dynamic>?;
    if (content == null) return null;
    final messageId = message['id'] as int?;
    if (messageId == null) return null;

    final caption =
        ((content['caption'] as Map<String, dynamic>?)?['text'] as String?) ??
            '';

    switch (content['@type']) {
      case 'messageVideo':
        final video = content['video'] as Map<String, dynamic>?;
        if (video == null) return null;
        final file = video['video'] as Map<String, dynamic>?;
        if (file == null) return null;
        return parseTelegramFileName(
          (video['file_name'] as String?)?.trim().isNotEmpty == true
              ? video['file_name'] as String
              : _fallbackName(caption, messageId),
          messageId: messageId,
          fileId: file['id'] as int? ?? 0,
          sizeBytes: (file['size'] as int?) ?? 0,
          durationSeconds: (video['duration'] as int?) ?? 0,
          caption: caption,
        );

      case 'messageDocument':
        final doc = content['document'] as Map<String, dynamic>?;
        if (doc == null) return null;
        final mime = (doc['mime_type'] as String?) ?? '';
        final name = (doc['file_name'] as String?) ?? '';
        if (!_looksLikeVideo(mime, name)) return null;
        final file = doc['document'] as Map<String, dynamic>?;
        if (file == null) return null;
        return parseTelegramFileName(
          name.isNotEmpty ? name : _fallbackName(caption, messageId),
          messageId: messageId,
          fileId: file['id'] as int? ?? 0,
          sizeBytes: (file['size'] as int?) ?? 0,
          caption: caption,
        );

      default:
        return null;
    }
  }

  static const _videoExtensions = [
    '.mkv', '.mp4', '.avi', '.mov', '.m4v', '.ts', '.webm',
  ];

  static bool _looksLikeVideo(String mimeType, String fileName) {
    if (mimeType.startsWith('video/')) return true;
    final lower = fileName.toLowerCase();
    return _videoExtensions.any(lower.endsWith);
  }

  /// Un fichier sans nom reste indexable via sa légende, souvent porteuse du
  /// titre — sinon on garde au moins une entrée identifiable.
  static String _fallbackName(String caption, int messageId) {
    final firstLine = caption.split('\n').first.trim();
    return firstLine.isNotEmpty ? firstLine : 'Message $messageId';
  }

  // -------------------------------------------------------------------------
  // Sérialisation du cache
  // -------------------------------------------------------------------------

  static Map<String, dynamic> _toJson(TelegramMedia m) => {
        'messageId': m.messageId,
        'fileId': m.fileId,
        'fileName': m.fileName,
        'title': m.title,
        'year': m.year,
        'kind': m.kind.name,
        'season': m.season,
        'episode': m.episode,
        'sizeBytes': m.sizeBytes,
        'durationSeconds': m.durationSeconds,
        'caption': m.caption,
        'languageTags': m.languageTags,
        'quality': m.quality,
      };

  static TelegramMedia _fromJson(Map<String, dynamic> j) => TelegramMedia(
        messageId: j['messageId'] as int? ?? 0,
        fileId: j['fileId'] as int? ?? 0,
        fileName: j['fileName'] as String? ?? '',
        title: j['title'] as String? ?? '',
        year: j['year'] as int? ?? 0,
        kind: j['kind'] == 'episode'
            ? TelegramMediaKind.episode
            : TelegramMediaKind.movie,
        season: j['season'] as int? ?? 0,
        episode: j['episode'] as int? ?? 0,
        sizeBytes: j['sizeBytes'] as int? ?? 0,
        durationSeconds: j['durationSeconds'] as int? ?? 0,
        caption: j['caption'] as String? ?? '',
        languageTags:
            (j['languageTags'] as List?)?.cast<String>() ?? const [],
        quality: j['quality'] as String? ?? '',
      );
}
