import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:iptv/config/theme/color/app_color.dart';
import 'package:iptv/config/theme/typography/app_typography.dart';

/// Feuille de sélection des pistes : qualité vidéo, audio et sous-titres.
void showTracksSheet(BuildContext context, Player player) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColor.surfaceColor,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _TracksSheet(player: player),
  );
}

class _TracksSheet extends StatefulWidget {
  final Player player;
  const _TracksSheet({required this.player});

  @override
  State<_TracksSheet> createState() => _TracksSheetState();
}

class _TracksSheetState extends State<_TracksSheet> {
  @override
  Widget build(BuildContext context) {
    final tracks = widget.player.state.tracks;
    final current = widget.player.state.track;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColor.textMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Qualité vidéo (variantes HLS) — utile surtout sur les flux adaptatifs.
            if (tracks.video.length > 2) ...[
              _section('Qualité'),
              ...tracks.video.map((t) => _tile(
                    label: _videoLabel(t),
                    selected: current.video == t,
                    onTap: () => _setVideo(t),
                  )),
              const SizedBox(height: 8),
            ],

            // Pistes audio (langues).
            if (tracks.audio.length > 2) ...[
              _section('Audio'),
              ...tracks.audio.map((t) => _tile(
                    label: _audioLabel(t),
                    selected: current.audio == t,
                    onTap: () => _setAudio(t),
                  )),
              const SizedBox(height: 8),
            ],

            // Sous-titres (avec option "Aucun").
            _section('Sous-titres'),
            _tile(
              label: 'Aucun',
              selected: current.subtitle == SubtitleTrack.no(),
              onTap: () => _setSubtitle(SubtitleTrack.no()),
            ),
            ...tracks.subtitle
                .where((t) => t != SubtitleTrack.no() && t != SubtitleTrack.auto())
                .map((t) => _tile(
                      label: _subtitleLabel(t),
                      selected: current.subtitle == t,
                      onTap: () => _setSubtitle(t),
                    )),
          ],
        ),
      ),
    );
  }

  void _setVideo(VideoTrack t) {
    widget.player.setVideoTrack(t);
    Navigator.pop(context);
  }

  void _setAudio(AudioTrack t) {
    widget.player.setAudioTrack(t);
    Navigator.pop(context);
  }

  void _setSubtitle(SubtitleTrack t) {
    widget.player.setSubtitleTrack(t);
    Navigator.pop(context);
  }

  String _videoLabel(VideoTrack t) {
    if (t == VideoTrack.auto()) return 'Automatique';
    final h = t.h;
    if (h != null && h > 0) return '${h}p';
    return t.title ?? t.id;
  }

  String _audioLabel(AudioTrack t) {
    if (t == AudioTrack.auto()) return 'Automatique';
    return t.title ?? t.language ?? t.id;
  }

  String _subtitleLabel(SubtitleTrack t) {
    return t.title ?? t.language ?? t.id;
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 4),
        child: Text(
          title.toUpperCase(),
          style: AppTypography.caption.copyWith(
            color: AppColor.primaryLight,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
      );

  Widget _tile({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: AppTypography.body1),
      trailing: selected
          ? const Icon(Icons.check_circle, color: AppColor.primaryColor, size: 20)
          : null,
      onTap: onTap,
    );
  }
}
