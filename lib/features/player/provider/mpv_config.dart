import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:iptv/core/storage/app_storage.dart';
import 'package:iptv/features/home/domain/entities/channel_entity.dart';

/// Presets de buffer : [bufferSize MB, cacheSecs, readaheadSecs, pauseWait secs].
const bufferPresets = [
  [32, 15, 10, 1], // 0 = Faible (faible latence, moins stable)
  [64, 60, 30, 3], // 1 = Normal (équilibré)
  [150, 180, 90, 5], // 2 = Élevé (pré-charge fortement, comme YouTube)
];

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
    await mpv.setProperty('demuxer-max-back-bytes', '${preset[0] ~/ 2}MiB');
    await mpv.setProperty('demuxer-readahead-secs', '${preset[2]}');

    // --- Cache-pause : remplir le buffer puis jouer sans coupure ---
    await mpv.setProperty('cache-pause', 'yes');
    await mpv.setProperty('cache-pause-initial', 'yes');
    await mpv.setProperty('cache-pause-wait', '${preset[3]}');

    // --- Résilience réseau : reconnexion automatique ---
    await mpv.setProperty('network-timeout', '30');
    await mpv.setProperty(
      'stream-lavf-o',
      'reconnect=1,reconnect_streamed=1,reconnect_delay_max=10,'
          'reconnect_on_network_error=1',
    );

    // --- Décodage matériel ---
    await mpv.setProperty('hwdec', 'auto');

    // --- Spécifique livestream ---
    if (channel.isLivestream) {
      await mpv.setProperty('prefetch-playlist', 'yes');
      await mpv.setProperty('loop-playlist', 'inf');
      await mpv.setProperty('demuxer-lavf-o', 'live_start_index=-3');
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
