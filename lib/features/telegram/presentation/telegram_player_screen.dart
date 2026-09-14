/// Lecture d'un fichier du canal Telegram.
///
/// Particularité par rapport au lecteur VOD existant : la source n'est pas une
/// URL mais un fichier que TDLib écrit progressivement sur le disque. On ne
/// peut donc pas ouvrir mpv immédiatement — il faut d'abord un préfixe
/// CONTIGU assez grand pour contenir l'en-tête du conteneur. D'où l'écran
/// d'attente avec progression, puis le basculement vers la vidéo.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:iptv/config/theme/color/app_color.dart';
import 'package:iptv/config/theme/typography/app_typography.dart';
import 'package:iptv/features/player/provider/mini_player_provider.dart';
import 'package:iptv/features/telegram/data/telegram_service.dart';
import 'package:iptv/features/telegram/domain/telegram_media.dart';
import 'package:iptv/features/telegram/provider/telegram_provider.dart';

class TelegramPlayerScreen extends StatefulWidget {
  final TelegramMedia media;

  const TelegramPlayerScreen({super.key, required this.media});

  @override
  State<TelegramPlayerScreen> createState() => _TelegramPlayerScreenState();
}

class _TelegramPlayerScreenState extends State<TelegramPlayerScreen> {
  Player? _player;
  VideoController? _controller;
  StreamSubscription<TelegramDownload>? _sub;

  TelegramDownload _download = const TelegramDownload();
  bool _started = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Libère le décodeur du live avant d'ouvrir le nôtre : deux instances mpv
    // simultanées font tomber l'app sur les appareils à décodeurs limités.
    context.read<MiniPlayerProvider>().releaseDecoder();
    WidgetsBinding.instance.addPostFrameCallback((_) => _listen());
  }

  void _listen() {
    final tg = context.read<TelegramProvider>();
    _sub = tg.prepare(widget.media).listen((update) {
      if (!mounted) return;
      setState(() => _download = update);
      // Dès que le préfixe suffit, on ouvre le lecteur — une seule fois.
      if (!_started && tg.canPlay(update)) _start(update);
    });
  }

  Future<void> _start(TelegramDownload download) async {
    _started = true;
    try {
      final player = Player();
      final controller = VideoController(player);
      await player.open(Media('file://${download.path}'));
      if (!mounted) {
        await player.dispose();
        return;
      }
      setState(() {
        _player = player;
        _controller = controller;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Lecture impossible : $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _player?.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    // Le téléchargement continue volontairement en arrière-plan : quitter le
    // lecteur une minute ne doit pas jeter 800 Mo déjà récupérés.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: _error.isNotEmpty
                  ? _buildError()
                  : _controller != null
                      ? Video(controller: _controller!, fit: BoxFit.contain)
                      : _buildBuffering(),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            // Une fois la lecture lancée, la progression du téléchargement
            // reste utile : elle explique une coupure si le réseau ralentit.
            if (_controller != null && !_download.isCompleted)
              Positioned(
                bottom: 8,
                left: 16,
                right: 16,
                child: _buildDownloadStrip(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBuffering() {
    final percent = (_download.progress * 100).clamp(0, 100);
    final hasSize = _download.expectedSize > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.media.displayTitle,
            textAlign: TextAlign.center,
            style: AppTypography.body1.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 220,
            child: LinearProgressIndicator(
              value: hasSize ? _download.progress : null,
              backgroundColor: Colors.white24,
              valueColor:
                  const AlwaysStoppedAnimation(AppColor.primaryColor),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            hasSize
                ? 'Préparation… ${percent.toStringAsFixed(0)} %'
                : 'Connexion à Telegram…',
            style: AppTypography.caption.copyWith(color: Colors.white70),
          ),
          if (widget.media.readableSize.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              widget.media.readableSize,
              style: AppTypography.caption.copyWith(color: Colors.white38),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDownloadStrip() {
    return Row(
      children: [
        const Icon(Icons.download, size: 14, color: Colors.white54),
        const SizedBox(width: 8),
        Expanded(
          child: LinearProgressIndicator(
            value: _download.expectedSize > 0 ? _download.progress : null,
            minHeight: 2,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation(AppColor.accentGreen),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${(_download.progress * 100).clamp(0, 100).toStringAsFixed(0)} %',
          style: AppTypography.caption.copyWith(color: Colors.white54),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline,
              color: AppColor.accentRed, size: 40),
          const SizedBox(height: 12),
          Text(
            _error,
            textAlign: TextAlign.center,
            style: AppTypography.body2.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
