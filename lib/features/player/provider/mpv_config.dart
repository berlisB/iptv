import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:iptv/core/storage/app_storage.dart';
import 'package:iptv/features/home/domain/entities/channel_entity.dart';

/// Presets de buffer : [bufferSize MB, cacheSecs, readaheadSecs, pauseWait secs].
/// pauseWait = durée minimale de buffer avant de (re)lancer la lecture — courte,
/// sinon chaque micro-coupure coûte plusieurs secondes de gel visible.
const bufferPresets = [
  [32, 20, 20, 2],  // 0 = Faible (latence réduite, buffer léger)
  [64, 60, 40, 3],  // 1 = Normal (équilibré)
  [150, 180, 90, 5], // 2 = Élevé (pré-charge fortement, stable)
];

/// Configure mpv pour un flux VOD (HLS direct).
Future<void> configureMpvForHls(Player? player) async {
  if (player == null) return;
  try {
    final platform = player.platform;
    if (platform == null) return;
    final mpv = platform as dynamic;

    // User-Agent pour éviter les blocages serveur
    await mpv.setProperty('user-agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36');

    // Buffer pour le VOD (contenu enregistré)
    await mpv.setProperty('cache', 'yes');
    await mpv.setProperty('cache-secs', '60');
    await mpv.setProperty('demuxer-max-bytes', '64MiB');
    await mpv.setProperty('demuxer-max-back-bytes', '32MiB');
    await mpv.setProperty('demuxer-readahead-secs', '30');

    // Cache-pause pour remplir avant de jouer
    await mpv.setProperty('cache-pause', 'yes');
    await mpv.setProperty('cache-pause-initial', 'yes');
    await mpv.setProperty('cache-pause-wait', '3');

    // Résilience réseau
    await mpv.setProperty('network-timeout', '12');
    await mpv.setProperty(
      'stream-lavf-o',
      'reconnect=1,reconnect_streamed=1,reconnect_delay_max=3,'
          'reconnect_on_network_error=1',
    );

    // Dé-multiplexeur en thread séparé (fluidité)
    await mpv.setProperty('demuxer-thread', 'yes');

    // Décodage matériel (auto-safe = évite les décodeurs capricieux)
    await mpv.setProperty('hwdec', 'auto-safe');

    // Audio: éviter les erreurs de décodage sur streams HLS multi-bitrate
    await mpv.setProperty('audio-pitch-correction', 'yes');
    await mpv.setProperty('audio-samplerate', '48000');
    await mpv.setProperty('audio-channels', 'stereo');

    // Accepter les certificats SSL potentiellement problématiques
    await mpv.setProperty('tls-verify', 'no');

    debugPrint('[VOD] mpv configuré pour HLS: cache=60s, hwdec=auto');
  } on AssertionError catch (_) {
    // Player détruit
  } catch (e) {
    debugPrint('[VOD] mpv config error: $e');
  }
}

/// Configure les propriétés natives mpv pour un streaming optimal et robuste.
Future<void> configureMpvForChannel(Player? player, ChannelEntity channel) async {
  if (player == null) return;
  try {
    final platform = player.platform;
    if (platform == null) return;
    final mpv = platform as dynamic;

    // --- Buffer adaptatif selon le réglage utilisateur ---
    final level = AppStorage.getBufferLevel().clamp(0, 2);
    final preset = bufferPresets[level];
    await mpv.setProperty('cache', 'yes');
    await mpv.setProperty('cache-secs', '${preset[1]}');
    await mpv.setProperty('demuxer-max-bytes', '${preset[0]}MiB');
    // Back-buffer minimal : pas de seek arrière sur du live, la mémoire sert
    // au readahead.
    await mpv.setProperty('demuxer-max-back-bytes', '8MiB');
    await mpv.setProperty('demuxer-readahead-secs', '${preset[2]}');

    // --- Cache-pause : remplir le buffer puis jouer sans coupure ---
    await mpv.setProperty('cache-pause', 'yes');
    await mpv.setProperty('cache-pause-initial', 'yes');
    await mpv.setProperty('cache-pause-wait', '${preset[3]}');

    // --- Résilience réseau : reconnexion rapide ---
    await mpv.setProperty('network-timeout', '12');
    await mpv.setProperty(
      'stream-lavf-o',
      'reconnect=1,reconnect_streamed=1,reconnect_delay_max=3,'
          'reconnect_on_network_error=1',
    );

    // --- Dé-multiplexeur en thread séparé (fluidité) ---
    await mpv.setProperty('demuxer-thread', 'yes');

    // --- Décodage matériel (auto-safe = évite les décodeurs capricieux) ---
    await mpv.setProperty('hwdec', 'auto-safe');

    // --- Spécifique livestream ---
    if (channel.isLivestream) {
      await mpv.setProperty('prefetch-playlist', 'yes');
      await mpv.setProperty('demuxer-lavf-o', 'live_start_index=-3');
      // Synchronisation sur l'horloge audio : rendu régulier. Surtout PAS
      // `untimed` (rend les frames sans horloge → vide le cache plus vite
      // qu'il ne se remplit = famine de buffer), ni `loop-playlist` (masque
      // les EOF en relançant en boucle sans notifier le failover Dart).
      await mpv.setProperty('video-sync', 'audio');
    } else {
      await mpv.setProperty('save-position-on-quit', 'yes');
    }

    // --- En-têtes HTTP par chaîne ---
    if (channel.httpHeaders.hasHeaders) {
      final headers = <String>[];
      if (channel.httpHeaders.referrer != null) {
        headers.add('Referer: ${channel.httpHeaders.referrer}');
      }
      if (channel.httpHeaders.httpOrigin != null) {
        headers.add('Origin: ${channel.httpHeaders.httpOrigin}');
      }
      if (channel.httpHeaders.userAgent != null) {
        await mpv.setProperty('user-agent', channel.httpHeaders.userAgent);
      }
      if (headers.isNotEmpty) {
        await mpv.setProperty('http-header-fields', headers.join(','));
      }
    }

    // --- Contournement SSL si la source l'exige (opt-in par flux) ---
    if (channel.httpHeaders.ignoreSSL) {
      await mpv.setProperty('tls-verify', 'no');
    }

    final levelNames = ['Faible', 'Normal', 'Élevé'];
    debugPrint('[IPTV] mpv configuré: buffer=${levelNames[level]}, '
        'cache=${preset[1]}s, hwdec=auto, live=${channel.isLivestream}');
  } on AssertionError catch (_) {
    // Player détruit entre create et configure — on ignore.
  } catch (e) {
    debugPrint('[IPTV] mpv config error (non-fatal): $e');
  }
}
