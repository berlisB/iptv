import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:iptv/config/theme/color/app_color.dart';
import 'package:iptv/config/theme/typography/app_typography.dart';
import 'package:iptv/features/home/domain/entities/channel_entity.dart';
import 'package:iptv/features/home/provider/home_provider.dart';
import 'package:iptv/features/player/provider/mini_player_provider.dart';

class PlayerScreen extends StatefulWidget {
  final ChannelEntity channel;

  const PlayerScreen({super.key, required this.channel});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool _showControls = true;
  bool _isFullScreen = false;

  MiniPlayerProvider get _miniProvider =>
      context.read<MiniPlayerProvider>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initPlayer();
    });
    _startHideControlsTimer();
  }

  void _initPlayer() {
    final miniProvider = context.read<MiniPlayerProvider>();

    if (miniProvider.currentChannel?.id == widget.channel.id &&
        miniProvider.hasActivePlayer) {
      miniProvider.expandFromMini();
    } else {
      miniProvider.playChannel(widget.channel);
    }

    context.read<HomeProvider>().onChannelWatched(widget.channel.id);
  }

  void _startHideControlsTimer() {
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _onTapVideo() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideControlsTimer();
  }

  void _toggleFullScreen() {
    setState(() => _isFullScreen = !_isFullScreen);
    if (_isFullScreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _hideAndGoBack() {
    final homeProvider = context.read<HomeProvider>();
    homeProvider.hideChannel(widget.channel.id);
    _miniProvider.stopAndClose();
    Navigator.of(context).pop();
  }

  void _goBackOrMinimize() {
    if (_isFullScreen) {
      _toggleFullScreen();
      return;
    }
    _miniProvider.minimizeToMini();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBackOrMinimize();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Consumer<MiniPlayerProvider>(
          builder: (context, mp, _) {
            final showError = mp.hasExhaustedRetries;

            return GestureDetector(
              onTap: _onTapVideo,
              child: Stack(
                children: [
                  // Video
                  if (mp.videoController != null)
                    Center(
                      child: Video(
                        controller: mp.videoController!,
                        controls: NoVideoControls,
                        fill: Colors.black,
                      ),
                    ),

                  // Buffering + connection status
                  if (mp.isBuffering && !showError)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            color: AppColor.primaryColor,
                            strokeWidth: 3,
                          ),
                          if (mp.connectionStatus.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                mp.connectionStatus,
                                style: AppTypography.caption.copyWith(
                                  color: AppColor.accentOrange,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                  // Error overlay (all retries exhausted)
                  if (showError) _buildErrorOverlay(mp),

                  // Controls
                  if (!showError)
                    AnimatedOpacity(
                      opacity: _showControls ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 250),
                      child: IgnorePointer(
                        ignoring: !_showControls,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.7),
                                Colors.transparent,
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.8),
                              ],
                              stops: const [0.0, 0.25, 0.75, 1.0],
                            ),
                          ),
                          child: SafeArea(
                            child: Column(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                _buildTopBar(mp),
                                _buildCenterControls(mp),
                                _buildBottomBar(mp),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildErrorOverlay(MiniPlayerProvider mp) {
    return Container(
      color: Colors.black87,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Still trying indicator
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    color: AppColor.accentOrange,
                    strokeWidth: 3,
                  ),
                ),
                const SizedBox(height: 20),
                Text('Chaîne inaccessible', style: AppTypography.heading3),
                const SizedBox(height: 8),
                Text(
                  widget.channel.cleanName,
                  style: AppTypography.body1
                      .copyWith(color: AppColor.primaryLight),
                ),
                const SizedBox(height: 8),
                Text(
                  'Aucune donnée reçue du serveur.\nL\'URL est peut-être hors ligne.',
                  style: AppTypography.body2,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => mp.retryChannel(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Relancer'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColor.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _hideAndGoBack,
                    icon: const Icon(Icons.visibility_off),
                    label: const Text('Masquer cette chaîne'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColor.accentOrange,
                      side: const BorderSide(color: AppColor.accentOrange),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _goBackOrMinimize,
                  child: Text(
                    'Retour',
                    style: AppTypography.body2
                        .copyWith(color: AppColor.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(MiniPlayerProvider mp) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: _goBackOrMinimize,
            icon: const Icon(Icons.keyboard_arrow_down,
                color: Colors.white, size: 30),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.channel.name,
                  style: AppTypography.heading3,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColor.liveColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'EN DIRECT',
                      style: AppTypography.caption.copyWith(
                        color: AppColor.liveColor,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => mp.enterPiP(),
            icon: const Icon(Icons.picture_in_picture_alt,
                color: Colors.white, size: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterControls(MiniPlayerProvider mp) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: () => mp.togglePlayPause(),
          iconSize: 64,
          icon: Icon(
            mp.isPlaying
                ? Icons.pause_circle_filled
                : Icons.play_circle_filled,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(MiniPlayerProvider mp) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          StreamBuilder<double>(
            stream: mp.player?.stream.volume,
            builder: (context, snapshot) {
              final volume = snapshot.data ?? 100.0;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    volume == 0
                        ? Icons.volume_off
                        : volume < 50
                            ? Icons.volume_down
                            : Icons.volume_up,
                    color: Colors.white,
                    size: 24,
                  ),
                  SizedBox(
                    width: 100,
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6),
                        activeTrackColor: AppColor.primaryColor,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: AppColor.primaryColor,
                        overlayColor:
                            AppColor.primaryColor.withValues(alpha: 0.2),
                      ),
                      child: Slider(
                        value: volume,
                        min: 0,
                        max: 100,
                        onChanged: (val) => mp.player?.setVolume(val),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColor.primaryColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.channel.group,
              style: AppTypography.caption
                  .copyWith(color: AppColor.primaryLight),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _goBackOrMinimize,
            icon: const Icon(Icons.close_fullscreen,
                color: Colors.white, size: 22),
          ),
          IconButton(
            onPressed: _toggleFullScreen,
            icon: Icon(
              _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
              color: Colors.white,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }
}
