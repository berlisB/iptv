import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:iptv/config/theme/color/app_color.dart';
import 'package:iptv/config/theme/typography/app_typography.dart';
import 'package:iptv/config/routes/route_utils.dart';
import 'package:iptv/features/player/provider/mini_player_provider.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  double _baseScale = 1.0;

  @override
  Widget build(BuildContext context) {
    return Consumer<MiniPlayerProvider>(
      builder: (context, provider, _) {
        if (!provider.isMiniMode || !provider.hasActivePlayer) {
          return const SizedBox.shrink();
        }

        final screenSize = MediaQuery.of(context).size;
        final w = provider.miniSize.width;
        final h = provider.miniSize.height;

        final clampedX = provider.position.dx.clamp(0.0, screenSize.width - w);
        final clampedY = provider.position.dy.clamp(0.0, screenSize.height - h - 80);

        return Positioned(
          left: clampedX,
          top: clampedY,
          child: GestureDetector(
            onTap: () {
              provider.expandFromMini();
              context.push(AppPage.player.path, extra: provider.currentChannel);
            },
            // Scale handles both drag (1 finger) and pinch-to-resize (2 fingers)
            onScaleStart: (_) {
              _baseScale = provider.miniSize.width;
            },
            onScaleUpdate: (details) {
              if (details.pointerCount >= 2) {
                // Pinch to resize
                final newWidth = _baseScale * details.scale;
                final delta = newWidth - provider.miniSize.width;
                provider.resizeMini(delta);
              } else {
                // Single finger drag
                provider.updatePosition(details.focalPointDelta);
              }
            },
            child: Material(
              elevation: 12,
              borderRadius: BorderRadius.circular(12),
              shadowColor: Colors.black54,
              child: Container(
                width: w,
                height: h,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColor.primaryColor.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Stack(
                    children: [
                      // Video
                      if (provider.videoController != null)
                        Video(
                          controller: provider.videoController!,
                          controls: NoVideoControls,
                          fill: Colors.black,
                        ),

                      // Buffering
                      if (provider.isBuffering)
                        const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: AppColor.primaryColor,
                              strokeWidth: 2,
                            ),
                          ),
                        ),

                      // Bottom info bar
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.85),
                              ],
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: AppColor.liveColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  provider.currentChannel?.name ?? '',
                                  style: AppTypography.caption.copyWith(
                                    fontSize: 9,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Top controls
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _MiniButton(
                              icon: provider.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              onTap: () => provider.togglePlayPause(),
                            ),
                            const SizedBox(width: 2),
                            _MiniButton(
                              icon: Icons.close,
                              onTap: () => provider.stopAndClose(),
                            ),
                          ],
                        ),
                      ),

                      // Resize handle (bottom-right corner)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            provider.resizeMini(details.delta.dx);
                          },
                          child: Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.bottomRight,
                            padding: const EdgeInsets.all(3),
                            child: Icon(
                              Icons.open_in_full,
                              size: 12,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MiniButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 14),
      ),
    );
  }
}
