import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:iptv/core/storage/app_storage.dart';
import 'package:iptv/features/home/domain/entities/channel_entity.dart';

class MiniPlayerProvider extends ChangeNotifier {
  Player? _player;
  VideoController? _videoController;
  ChannelEntity? _currentChannel;
  bool _isMiniMode = false;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _hasEverPlayed = false;
  bool _disposed = false;
  int _connectionSeconds = 0;
  Offset _position = const Offset(16, 100);
  Size _miniSize = const Size(180, 110);
  StreamSubscription? _playingSub;
  StreamSubscription? _bufferSub;
  StreamSubscription? _widthSub;
  Timer? _connectionTimer;
  Timer? _deadTimer;
  Timer? _confirmTimer;

  /// Has mpv established a connection and started receiving data?
  bool _hasConnected = false;

  /// Smooth playback tracking: counts continuous seconds without buffering
  bool _confirmedThisSession = false;

  /// Dead URL timeout: if mpv hasn't connected at all after this, URL is truly dead.
  /// Adapts to buffer level: low=12s, normal=18s, high=30s
  static const _deadTimeoutByLevel = [12, 18, 30];

  static const _pipChannel = MethodChannel('com.example.iptv/pip');

  Player? get player => _player;
  VideoController? get videoController => _videoController;
  ChannelEntity? get currentChannel => _currentChannel;
  bool get isMiniMode => _isMiniMode;
  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  bool get hasActivePlayer => _player != null && _currentChannel != null;
  Offset get position => _position;
  Size get miniSize => _miniSize;
  int get connectionSeconds => _connectionSeconds;
  bool get hasEverPlayed => _hasEverPlayed;

  /// True when URL appears dead (no connection at all after timeout)
  bool get isUrlDead => !_hasConnected && !_hasEverPlayed && _connectionSeconds > _deadTimeout;

  int get _deadTimeout => _deadTimeoutByLevel[AppStorage.getBufferLevel().clamp(0, 2)];

  String get connectionStatus {
    if (_hasEverPlayed) return '';
    if (isUrlDead) return '';
    if (_hasConnected) return 'Chargement du flux... ${_connectionSeconds}s';
    if (_connectionSeconds > 3) return 'Connexion... ${_connectionSeconds}s';
    return '';
  }

  // Legacy getters for UI compatibility
  int get retryCount => 0;
  bool get isRetrying => false;
  bool get hasExhaustedRetries => isUrlDead;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  /// Buffer presets: [bufferSize MB, cacheSecs, readaheadSecs, pauseWait secs]
  static const _bufferPresets = [
    [32, 15, 10, 1],   // 0 = Faible (low latency, less stable)
    [64, 60, 30, 3],   // 1 = Normal (balanced)
    [150, 180, 90, 5], // 2 = Élevé (YouTube-like, pre-buffers heavily)
  ];

  void _createPlayer() {
    _playingSub?.cancel();
    _bufferSub?.cancel();
    _widthSub?.cancel();
    _player?.dispose();

    final level = AppStorage.getBufferLevel().clamp(0, 2);
    final preset = _bufferPresets[level];

    _player = Player(
      configuration: PlayerConfiguration(
        bufferSize: preset[0] * 1024 * 1024,
        logLevel: MPVLogLevel.warn,
      ),
    );

    _videoController = VideoController(_player!);

    _playingSub = _player!.stream.playing.listen((playing) {
      if (_disposed) return;
      _isPlaying = playing;
      _safeNotify();
    });

    _bufferSub = _player!.stream.buffering.listen((buffering) {
      if (_disposed) return;
      _isBuffering = buffering;

      // Key insight: if mpv fires buffering=true, it means it HAS connected
      // to the server and is downloading data. Cancel the dead-URL timer.
      if (buffering && !_hasConnected) {
        _hasConnected = true;
        _deadTimer?.cancel();
        _deadTimer = null;
        debugPrint('[IPTV] Connection established - downloading data, '
            'waiting for buffer to fill...');
      }

      // Smooth playback detection for auto-confirm:
      // When buffering stops (= playing smoothly), start a 30s timer.
      // If buffering resumes before 30s, cancel it.
      if (_hasEverPlayed && !_confirmedThisSession) {
        if (!buffering) {
          // Playing smoothly — start confirm countdown
          _confirmTimer?.cancel();
          _confirmTimer = Timer(const Duration(seconds: 30), () {
            _autoConfirmChannel();
          });
        } else {
          // Buffering again — reset countdown
          _confirmTimer?.cancel();
          _confirmTimer = null;
        }
      }

      _safeNotify();
    });

    _widthSub = _player!.stream.width.listen((width) {
      if (_disposed) return;
      if (width != null && width > 0) {
        debugPrint('[IPTV] Got video frames: ${width}px wide');
        _hasEverPlayed = true;
        _hasConnected = true;
        _cancelTimers();
        _safeNotify();
      }
    });
  }

  /// Configure mpv native properties for optimal streaming
  Future<void> _configureMpvForChannel(ChannelEntity channel) async {
    if (_player == null || _disposed) return;

    try {
      final platform = _player?.platform;
      if (platform == null) return;

      final nativePlayer = platform as dynamic;

      // --- Streaming performance (adaptive buffer) ---
      final level = AppStorage.getBufferLevel().clamp(0, 2);
      final preset = _bufferPresets[level];
      final cacheSecs = preset[1];
      final readaheadSecs = preset[2];
      final pauseWait = preset[3];

      await nativePlayer.setProperty('cache', 'yes');
      await nativePlayer.setProperty('cache-secs', '$cacheSecs');
      await nativePlayer.setProperty('demuxer-max-bytes', '${preset[0]}MiB');
      await nativePlayer.setProperty('demuxer-max-back-bytes', '${preset[0] ~/ 2}MiB');
      await nativePlayer.setProperty('demuxer-readahead-secs', '$readaheadSecs');

      // --- Cache-pause: pause briefly to fill buffer, then play smoothly ---
      // This is the "YouTube" behavior: buffer first, play without interruption
      await nativePlayer.setProperty('cache-pause', 'yes');
      await nativePlayer.setProperty('cache-pause-initial', 'yes');
      await nativePlayer.setProperty('cache-pause-wait', '$pauseWait');

      // --- Network resilience ---
      // Long network timeout for slow connections
      await nativePlayer.setProperty('network-timeout', '30');
      await nativePlayer.setProperty(
        'stream-lavf-o',
        'reconnect=1,reconnect_streamed=1,reconnect_delay_max=10,reconnect_on_network_error=1',
      );

      // --- Hardware decoding ---
      await nativePlayer.setProperty('hwdec', 'auto');

      // --- Livestream specific ---
      if (channel.isLivestream) {
        await nativePlayer.setProperty('prefetch-playlist', 'yes');
        await nativePlayer.setProperty('loop-playlist', 'inf');
        // Start near live edge for HLS
        await nativePlayer.setProperty('demuxer-lavf-o', 'live_start_index=-3');
      } else {
        // VOD: save position for resume
        await nativePlayer.setProperty('save-position-on-quit', 'yes');
      }

      // --- Per-channel HTTP headers ---
      if (channel.httpHeaders.hasHeaders) {
        final headers = <String>[];

        if (channel.httpHeaders.referrer != null) {
          headers.add('Referer: ${channel.httpHeaders.referrer}');
        }
        if (channel.httpHeaders.httpOrigin != null) {
          headers.add('Origin: ${channel.httpHeaders.httpOrigin}');
        }
        if (channel.httpHeaders.userAgent != null) {
          await nativePlayer.setProperty(
            'user-agent',
            channel.httpHeaders.userAgent,
          );
        }

        if (headers.isNotEmpty) {
          await nativePlayer.setProperty(
            'http-header-fields',
            headers.join(','),
          );
        }
      }

      // --- SSL bypass if needed ---
      if (channel.httpHeaders.ignoreSSL) {
        await nativePlayer.setProperty('tls-verify', 'no');
      }

      final levelNames = ['Faible', 'Normal', 'Élevé'];
      debugPrint('[IPTV] mpv configured: buffer=${levelNames[level]}, '
          'cache=${cacheSecs}s, readahead=${readaheadSecs}s, '
          'pause-wait=${pauseWait}s, hwdec=auto, '
          'prefetch=${channel.isLivestream}');
    } on AssertionError catch (_) {
      // Player was disposed between create and configure - ignore
    } catch (e) {
      debugPrint('[IPTV] mpv config error (non-fatal): $e');
    }
  }

  void _autoConfirmChannel() {
    if (_disposed || _currentChannel == null || _confirmedThisSession) return;
    _confirmedThisSession = true;
    AppStorage.confirmChannel(_currentChannel!.id);
    debugPrint('[IPTV] Channel auto-confirmed as reliable: '
        '${_currentChannel!.name}');
  }

  Map<String, String>? _buildHeaders(ChannelEntity channel) {
    if (!channel.httpHeaders.hasHeaders) return null;
    return {
      if (channel.httpHeaders.referrer != null)
        'Referer': channel.httpHeaders.referrer!,
      if (channel.httpHeaders.httpOrigin != null)
        'Origin': channel.httpHeaders.httpOrigin!,
    };
  }

  Future<void> playChannel(ChannelEntity channel) async {
    if (_disposed) return;

    debugPrint('[IPTV] playChannel: ${channel.name} -> ${channel.url}');

    _currentChannel = channel;
    _isMiniMode = false;
    _hasEverPlayed = false;
    _hasConnected = false;
    _confirmedThisSession = false;
    _connectionSeconds = 0;
    _isBuffering = true;

    _createPlayer();
    _safeNotify();

    // Configure mpv native options before opening
    await _configureMpvForChannel(channel);

    _startConnectionTracking();

    // Fire-and-forget: don't await, let mpv connect in background
    _player!.open(Media(channel.url, httpHeaders: _buildHeaders(channel)));
  }

  void _startConnectionTracking() {
    _cancelTimers();

    // Connection counter (for UI display)
    _connectionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || _hasEverPlayed) {
        _cancelTimers();
        return;
      }
      _connectionSeconds++;

      if (_hasConnected) {
        debugPrint('[IPTV] Buffering... ${_connectionSeconds}s '
            '(connected, filling cache)');
      } else {
        debugPrint('[IPTV] Connecting... ${_connectionSeconds}s');
      }
      _safeNotify();
    });

    // Dead-URL timer: only fires if mpv NEVER establishes a connection.
    // If mpv starts buffering (= connected), this timer is cancelled.
    final timeout = _deadTimeout;
    _deadTimer = Timer(Duration(seconds: timeout), () {
      if (_disposed || _hasEverPlayed || _hasConnected) return;
      debugPrint('[IPTV] URL appears dead after ${timeout}s '
          '(no connection established)');
      // Don't kill the player - it might still connect.
      // Just notify UI so it can show an option to retry or go back.
      _safeNotify();
    });
  }

  void _cancelTimers() {
    _connectionTimer?.cancel();
    _deadTimer?.cancel();
    _confirmTimer?.cancel();
    _connectionTimer = null;
    _deadTimer = null;
    _confirmTimer = null;
  }

  Future<void> retryChannel() async {
    if (_disposed || _currentChannel == null) return;
    _connectionSeconds = 0;
    _hasEverPlayed = false;
    _hasConnected = false;
    _confirmedThisSession = false;
    _isBuffering = true;

    _createPlayer();
    _safeNotify();

    await _configureMpvForChannel(_currentChannel!);
    _startConnectionTracking();
    _player!.open(Media(
      _currentChannel!.url,
      httpHeaders: _buildHeaders(_currentChannel!),
    ));
  }

  void minimizeToMini() {
    if (_disposed || _player == null || _currentChannel == null) return;
    _isMiniMode = true;
    _safeNotify();
  }

  void expandFromMini() {
    if (_disposed) return;
    _isMiniMode = false;
    _safeNotify();
  }

  Future<void> togglePlayPause() async {
    if (_disposed) return;
    await _player?.playOrPause();
  }

  void updatePosition(Offset delta) {
    _position = Offset(
      _position.dx + delta.dx,
      _position.dy + delta.dy,
    );
    _safeNotify();
  }

  void setPosition(Offset pos) {
    _position = pos;
    _safeNotify();
  }

  void resizeMini(double delta) {
    const minW = 120.0;
    const maxW = 360.0;
    const aspectRatio = 16.0 / 9.0;
    final newWidth = (_miniSize.width + delta).clamp(minW, maxW);
    _miniSize = Size(newWidth, newWidth / aspectRatio);
    _safeNotify();
  }

  Future<void> stopAndClose() async {
    _cancelTimers();
    _isMiniMode = false;
    _currentChannel = null;
    _hasEverPlayed = false;
    _hasConnected = false;
    _confirmedThisSession = false;
    _connectionSeconds = 0;
    _isBuffering = false;
    try {
      await _player?.stop();
    } catch (_) {}
    _safeNotify();
  }

  Future<void> enterPiP() async {
    try {
      await _pipChannel.invokeMethod('enterPiP');
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTimers();
    _playingSub?.cancel();
    _bufferSub?.cancel();
    _widthSub?.cancel();
    _playingSub = null;
    _bufferSub = null;
    _widthSub = null;
    try {
      _player?.dispose();
    } catch (_) {}
    _player = null;
    super.dispose();
  }
}
