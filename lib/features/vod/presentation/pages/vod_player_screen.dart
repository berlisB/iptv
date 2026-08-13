import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:iptv/config/theme/color/app_color.dart';
import 'package:iptv/core/storage/app_storage.dart';
import 'package:iptv/features/player/provider/mpv_config.dart';
import 'package:iptv/features/player/presentation/widgets/player_tracks_sheet.dart';
import 'package:media_kit/media_kit.dart';

/// Écran de lecture VOD — joue le flux HLS directement avec media_kit.
/// Si pas de HLS direct, fallback sur WebView avec interception JS.
class VodPlayerScreen extends StatefulWidget {
  final String embedUrl;
  final String? directHlsUrl;
  final String title;
  final Map<String, String>? headers;
  final int? tmdbId;
  final int? season;
  final int? episode;
  final int? totalEpisodesInSeason;
  final bool isTv;

  const VodPlayerScreen({
    super.key,
    required this.embedUrl,
    this.directHlsUrl,
    required this.title,
    this.headers,
    this.tmdbId,
    this.season,
    this.episode,
    this.totalEpisodesInSeason,
    this.isTv = false,
  });

  @override
  State<VodPlayerScreen> createState() => _VodPlayerScreenState();
}

class _VodPlayerScreenState extends State<VodPlayerScreen> {
  Player? _player;
  VideoController? _videoController;
  WebViewController? _webController;
  bool _isLoading = true;
  bool _hasError = false;
  bool _isFullScreen = false;
  bool _useWebView = false;
  bool _hlsFound = false;
  String? _errorMessage;
  Timer? _errorDebounceTimer;
  int _errorCount = 0;
  static const _maxErrorsBeforeShow = 3;

  // Auto-next episode
  bool _showNextEpisode = false;
  Timer? _nextEpisodeTimer;
  static const _nextEpisodeCountdown = 10;

  // Skip intro
  bool _showSkipIntro = false;
  Timer? _skipIntroTimer;

  // External subtitles
  String? _externalSubtitlePath;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  void _initPlayer() {
    if (widget.directHlsUrl != null && widget.directHlsUrl!.isNotEmpty) {
      _initMediaPlayer(widget.directHlsUrl!);
    } else {
      _initWebViewWithIntercept();
    }
  }

  Future<void> _initMediaPlayer(String hlsUrl) async {
    debugPrint('[VodPlayer] Playing HLS: $hlsUrl');
    _player = Player();
    _videoController = VideoController(_player!);

    _player!.stream.buffering.listen((buffering) {
      if (mounted) setState(() => _isLoading = buffering);
    });

    _player!.stream.playing.listen((playing) {
      if (playing && mounted) {
        _errorCount = 0;
        _errorDebounceTimer?.cancel();
        if (_hasError) {
          setState(() {
            _hasError = false;
            _errorMessage = null;
          });
        }
      }
    });

    _player!.stream.width.listen((width) {
      if (width != null && width > 0 && mounted) {
        setState(() => _isLoading = false);
      }
    });

    _player!.stream.error.listen((error) {
      debugPrint('[VodPlayer] Media error: $error');
      _errorCount++;
      if (_errorCount >= _maxErrorsBeforeShow && mounted) {
        _errorDebounceTimer?.cancel();
        _errorDebounceTimer = Timer(const Duration(seconds: 2), () {
          if (mounted && _errorCount >= _maxErrorsBeforeShow) {
            setState(() {
              _hasError = true;
              _errorMessage = 'Erreur de lecture: $error';
            });
          }
        });
      }
    });

    // Auto-sélection des pistes FR quand les tracks deviennent disponibles.
    _player!.stream.tracks.listen((tracks) {
      if (!mounted || _frTrackApplied) return;
      _applyFrenchTracks(tracks);
    });

    // Détection fin d'épisode → auto-next.
    _player!.stream.completed.listen((completed) {
      if (!mounted || !widget.isTv || completed != true) return;
      _onEpisodeComplete();
    });

    // Skip intro : afficher le bouton pendant les 15 premières secondes
    // (début typique d'un intro de série).
    _skipIntroTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showSkipIntro = true);
    });
    Timer(const Duration(seconds: 20), () {
      if (mounted) setState(() => _showSkipIntro = false);
    });

    await configureMpvForHls(_player!);

    // Set HTTP headers via mpv properties
    if (widget.headers != null && widget.headers!.isNotEmpty) {
      try {
        final platform = _player!.platform;
        if (platform != null) {
          final mpv = platform as dynamic;
          final headerFields = widget.headers!
              .entries
              .map((e) => '${e.key}: ${e.value}')
              .toList();
          await mpv.setProperty('http-header-fields', headerFields.join(','));
          debugPrint('[VodPlayer] Set http-header-fields: $headerFields');
        }
      } catch (e) {
        debugPrint('[VodPlayer] Failed to set headers via mpv: $e');
      }
    }

    _player!.open(Media(hlsUrl));

    // Charger les sous-titres externes si présents.
    if (_externalSubtitlePath != null) {
      _loadExternalSubtitle(_externalSubtitlePath!);
    }
  }

  bool _frTrackApplied = false;

  void _applyFrenchTracks(Tracks tracks) {
    if (_frTrackApplied) return;

    AudioTrack? frAudio;
    for (final t in tracks.audio) {
      final lang = (t.language ?? '').toLowerCase();
      final title = (t.title ?? '').toLowerCase();
      if (lang.contains('fr') || title.contains('français') ||
          title.contains('french') || title.contains('fr')) {
        frAudio = t;
        break;
      }
    }

    if (frAudio != null) {
      _player?.setAudioTrack(frAudio);
      debugPrint('[VodPlayer] Audio FR sélectionné: ${frAudio.title ?? frAudio.language}');
    }

    SubtitleTrack? frSub;
    for (final t in tracks.subtitle) {
      if (t == SubtitleTrack.no() || t == SubtitleTrack.auto()) continue;
      final lang = (t.language ?? '').toLowerCase();
      final title = (t.title ?? '').toLowerCase();
      if (lang.contains('fr') || title.contains('français') ||
          title.contains('french') || title.contains('fr')) {
        frSub = t;
        break;
      }
    }

    if (frSub != null) {
      _player?.setSubtitleTrack(frSub);
      debugPrint('[VodPlayer] Sous-titres FR sélectionnés: ${frSub.title ?? frSub.language}');
    }

    _frTrackApplied = true;
  }

  // --- Auto-next episode ---

  void _onEpisodeComplete() {
    if (!mounted || !widget.isTv) return;

    // Marquer l'épisode comme vu.
    if (widget.tmdbId != null && widget.season != null && widget.episode != null) {
      AppStorage.setEpisodeWatched(widget.tmdbId!,
          season: widget.season!, episode: widget.episode!);
    }

    final hasNext = widget.totalEpisodesInSeason != null &&
        widget.episode != null &&
        widget.episode! < widget.totalEpisodesInSeason!;

    if (hasNext) {
      setState(() => _showNextEpisode = true);
      _nextEpisodeTimer = Timer(const Duration(seconds: _nextEpisodeCountdown), () {
        if (mounted && _showNextEpisode) {
          _playNextEpisode();
        }
      });
    }
  }

  void _playNextEpisode() {
    if (!mounted) return;
    final nextEpisode = (widget.episode ?? 1) + 1;

    // Mettre à jour la progression.
    if (widget.tmdbId != null && widget.season != null) {
      AppStorage.saveWatchProgress(widget.tmdbId!,
          season: widget.season!, episode: nextEpisode);
    }

    // On ne peut pas naviguer directement ici car on ne connaît pas l'URL du
    // prochain épisode. On fait juste un pop et le detail sheet se chargera
    // de la reprise.
    Navigator.of(context).pop({'nextEpisode': nextEpisode, 'season': widget.season});
  }

  void _cancelNextEpisode() {
    _nextEpisodeTimer?.cancel();
    setState(() => _showNextEpisode = false);
  }

  // --- Sous-titres externes ---

  Future<void> _pickExternalSubtitle() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['srt', 'ass', 'ssa', 'vtt'],
    );

    if (result != null && result.files.single.path != null) {
      _externalSubtitlePath = result.files.single.path!;
      _loadExternalSubtitle(_externalSubtitlePath!);
    }
  }

  void _loadExternalSubtitle(String path) {
    if (_player == null) return;
    try {
      _player!.setSubtitleTrack(SubtitleTrack.uri(path));
      debugPrint('[VodPlayer] Sous-titre externe chargé: $path');
    } catch (e) {
      debugPrint('[VodPlayer] Erreur chargement sous-titre: $e');
    }
  }

  // --- WebView ---

  void _initWebViewWithIntercept() {
    _useWebView = true;
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'HlsInterceptor',
        onMessageReceived: (JavaScriptMessage message) {
          final url = message.message;
          if (url.isNotEmpty && !_hlsFound) {
            _hlsFound = true;
            debugPrint('[VodPlayer] Intercepted HLS URL: $url');
            if (mounted) {
              setState(() {
                _useWebView = false;
                _isLoading = true;
              });
              _webController = null;
              _initMediaPlayer(url);
            }
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _isLoading = false);
              _injectHlsIntercept();
            }
          },
          onWebResourceError: (error) {
            debugPrint('[VodPlayer] WebView error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.embedUrl));
  }

  void _injectHlsIntercept() {
    _webController?.runJavaScript('''
      (function() {
        const origOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function(method, url) {
          if (typeof url === 'string' && (url.includes('.m3u8') || url.includes('playlist'))) {
            window.HlsInterceptor.postMessage(url);
          }
          return origOpen.apply(this, arguments);
        };

        const origFetch = window.fetch;
        window.fetch = function(input, init) {
          const url = typeof input === 'string' ? input : (input.url || '');
          if (url.includes('.m3u8') || url.includes('playlist')) {
            window.HlsInterceptor.postMessage(url);
          }
          return origFetch.apply(this, arguments);
        };

        document.querySelectorAll('video').forEach(video => {
          const observer = new MutationObserver((mutations) => {
            mutations.forEach((mutation) => {
              if (mutation.attributeName === 'src') {
                const src = video.src || video.getAttribute('src');
                if (src && (src.includes('.m3u8') || src.includes('playlist'))) {
                  window.HlsInterceptor.postMessage(src);
                }
              }
            });
          });
          observer.observe(video, { attributes: true, attributeFilter: ['src'] });
          if (video.src && (video.src.includes('.m3u8') || video.src.includes('playlist'))) {
            window.HlsInterceptor.postMessage(video.src);
          }
        });

        if (window.Hls) {
          const origLoadSource = window.Hls.prototype.loadSource;
          window.Hls.prototype.loadSource = function(url) {
            window.HlsInterceptor.postMessage(url);
            return origLoadSource.apply(this, arguments);
          };
        }

        console.log('[HLS Interceptor] Installed');
      })();
    ''');

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _useWebView) {
        _webController?.runJavaScript('''
          document.querySelectorAll('button[aria-label*="Play"], button[aria-label*="play"], .vjs-big-play-button, [class*="play"]').forEach(btn => btn.click());
          document.querySelectorAll('video').forEach(v => v.play().catch(e => {}));
        ''');
      }
    });

    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _useWebView) {
        _webController?.runJavaScript('''
          document.querySelectorAll('video').forEach(v => {
            if (v.src && v.src.includes('.m3u8')) window.HlsInterceptor.postMessage(v.src);
            v.play().catch(e => {});
          });
        ''');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: Stack(
                children: [
                  if (!_useWebView && _videoController != null)
                    Center(
                      child: Video(
                        controller: _videoController!,
                        controls: MaterialVideoControls,
                      ),
                    ),
                  if (_useWebView && _webController != null)
                    WebViewWidget(controller: _webController!),
                  if (_isLoading)
                    Container(
                      color: Colors.black,
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: AppColor.primaryColor),
                            SizedBox(height: 16),
                            Text('Chargement du stream...',
                                style: TextStyle(color: Colors.white54)),
                          ],
                        ),
                      ),
                    ),
                  if (_hasError) _buildError(),
                  if (_showNextEpisode) _buildNextEpisodeOverlay(),
                  if (_showSkipIntro && !_showNextEpisode)
                    _buildSkipIntroButton(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_player != null)
            IconButton(
              icon: Icon(
                _player!.state.playing ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
              onPressed: () => _player!.playOrPause(),
            ),
          if (_player != null)
            IconButton(
              icon: const Icon(Icons.tune_rounded, color: Colors.white, size: 22),
              onPressed: () => showTracksSheet(context, _player!),
            ),
          IconButton(
            icon: const Icon(Icons.subtitles, color: Colors.white, size: 22),
            onPressed: _pickExternalSubtitle,
            tooltip: 'Sous-titres externes (.srt/.ass)',
          ),
          IconButton(
            icon: Icon(
              _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
              color: Colors.white,
            ),
            onPressed: _toggleFullScreen,
          ),
        ],
      ),
    );
  }

  Widget _buildNextEpisodeOverlay() {
    final nextEp = (widget.episode ?? 1) + 1;
    return Positioned(
      bottom: 80,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppColor.primaryColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Épisode suivant',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'S${widget.season}:E$nextEp',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${_nextEpisodeCountdown}s',
              style: TextStyle(
                color: AppColor.primaryColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: _cancelNextEpisode,
              child: const Text('Annuler',
                  style: TextStyle(color: Colors.white54)),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _playNextEpisode,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColor.primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Lire'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkipIntroButton() {
    return Positioned(
      bottom: 80,
      right: 16,
      child: ElevatedButton(
        onPressed: () {
          // Sauter 90 secondes (intro typique).
          _player?.seek(_player!.state.position + const Duration(seconds: 90));
          setState(() => _showSkipIntro = false);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.15),
          foregroundColor: Colors.white,
          side: BorderSide(
              color: Colors.white.withValues(alpha: 0.3)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24)),
        ),
        child: const Text('Passer l\'intro',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColor.surfaceColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            const Text('Erreur de lecture',
                style: TextStyle(color: Colors.white, fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Le stream n\'est pas disponible.',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _hasError = false;
                      _isLoading = true;
                      _errorMessage = null;
                      _hlsFound = false;
                      _errorCount = 0;
                      _frTrackApplied = false;
                    });
                    _errorDebounceTimer?.cancel();
                    _player?.dispose();
                    _player = null;
                    _videoController = null;
                    _initPlayer();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColor.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Réessayer'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white24),
                  ),
                  child: const Text('Retour'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _toggleFullScreen() {
    if (_isFullScreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    setState(() => _isFullScreen = !_isFullScreen);
  }

  @override
  void dispose() {
    _errorDebounceTimer?.cancel();
    _nextEpisodeTimer?.cancel();
    _skipIntroTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _player?.dispose();
    super.dispose();
  }
}
