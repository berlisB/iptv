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
  int _retryCount = 0;
  int _connectionSeconds = 0;
  Offset _position = const Offset(16, 100);
  Size _miniSize = const Size(180, 110);
  StreamSubscription? _playingSub;
  StreamSubscription? _bufferSub;
  StreamSubscription? _widthSub;
  Timer? _connectionTimer;
  Timer? _timeoutTimer;

  static const int _maxRetries = 2;
  static const int _timeoutSeconds = 10;

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
  int get retryCount => _retryCount;
  int get connectionSeconds => _connectionSeconds;
  bool get isRetrying => _retryCount > 0 && !_hasEverPlayed;
  String get connectionStatus {
    if (_hasEverPlayed) return '';
    if (_retryCount > 0) return 'Tentative $_retryCount/$_maxRetries...';
    if (_connectionSeconds > 3) return 'Connexion... ${_connectionSeconds}s';
    return '';
  }

  bool get hasExhaustedRetries =>
      _retryCount > _maxRetries && !_hasEverPlayed;

  bool get hasEverPlayed => _hasEverPlayed;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  void _createPlayer() {
    _playingSub?.cancel();
    _bufferSub?.cancel();
    _widthSub?.cancel();
    _player?.dispose();

    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 64 * 1024 * 1024,
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
      _safeNotify();
    });

    _widthSub = _player!.stream.width.listen((width) {
      if (_disposed) return;
      if (width != null && width > 0) {
        debugPrint('[IPTV] Got video frames: ${width}px wide');
        _hasEverPlayed = true;
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

      // --- Streaming performance ---
      await nativePlayer.setProperty('cache', 'yes');
      await nativePlayer.setProperty('cache-secs', '30');
      await nativePlayer.setProperty('demuxer-max-bytes', '64MiB');
      await nativePlayer.setProperty('demuxer-max-back-bytes', '32MiB');
      await nativePlayer.setProperty('demuxer-readahead-secs', '20');

      // --- Network resilience ---
      await nativePlayer.setProperty('network-timeout', '15');
      await nativePlayer.setProperty(
        'stream-lavf-o',
        'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5,reconnect_on_network_error=1',
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

      debugPrint('[IPTV] mpv configured: cache=yes, hwdec=auto, '
          'prefetch=${channel.isLivestream}, '
          'headers=${channel.httpHeaders.hasHeaders}');
    } on AssertionError catch (_) {
      // Player was disposed between create and configure - ignore
    } catch (e) {
      debugPrint('[IPTV] mpv config error (non-fatal): $e');
    }
  }

  Future<void> playChannel(ChannelEntity channel) async {
    if (_disposed) return;

    debugPrint('[IPTV] playChannel: ${channel.name} -> ${channel.url}');

    _currentChannel = channel;
    _isMiniMode = false;
    _hasEverPlayed = false;
    _retryCount = 0;
    _connectionSeconds = 0;
    _isBuffering = true;

    _createPlayer();
    _safeNotify();

    // Configure mpv native options before opening
    await _configureMpvForChannel(channel);

    _startConnectionTracking();

    // Pass HTTP headers via Media if available
    final Map<String, String>? mediaHeaders =
        channel.httpHeaders.hasHeaders
            ? {
                if (channel.httpHeaders.referrer != null)
                  'Referer': channel.httpHeaders.referrer!,
                if (channel.httpHeaders.httpOrigin != null)
                  'Origin': channel.httpHeaders.httpOrigin!,
              }
            : null;

    _player!.open(Media(
      channel.url,
      httpHeaders: mediaHeaders,
    ));
  }

  void _startConnectionTracking() {
    _cancelTimers();

    _connectionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || _hasEverPlayed) {
        _cancelTimers();
        return;
      }
      _connectionSeconds++;
      debugPrint(
          '[IPTV] Connecting... ${_connectionSeconds}s (retry: $_retryCount)');
      _safeNotify();
    });

    _timeoutTimer = Timer(Duration(seconds: _timeoutSeconds), () {
      debugPrint('[IPTV] Timeout after ${_timeoutSeconds}s');
      _onConnectionTimeout();
    });
  }

  void _onConnectionTimeout() {
    if (_disposed || _hasEverPlayed || _currentChannel == null) return;

    _retryCount++;
    debugPrint('[IPTV] Retry $_retryCount/$_maxRetries');

    if (_retryCount <= _maxRetries) {
      _connectionSeconds = 0;
      _safeNotify();

      _createPlayer();
      _configureMpvForChannel(_currentChannel!);
      _player!.open(Media(
        _currentChannel!.url,
        httpHeaders: _currentChannel!.httpHeaders.hasHeaders
            ? {
                if (_currentChannel!.httpHeaders.referrer != null)
                  'Referer': _currentChannel!.httpHeaders.referrer!,
                if (_currentChannel!.httpHeaders.httpOrigin != null)
                  'Origin': _currentChannel!.httpHeaders.httpOrigin!,
              }
            : null,
      ));

      _timeoutTimer?.cancel();
      _timeoutTimer = Timer(Duration(seconds: _timeoutSeconds), () {
        _onConnectionTimeout();
      });
    } else {
      debugPrint('[IPTV] All retries exhausted, adding to local blocklist');
      _cancelTimers();
      _isBuffering = false;
      // Auto-add to local blocklist
      AppStorage.addToBlocklist(_currentChannel!.url);
      _safeNotify();
    }
  }

  void _cancelTimers() {
    _connectionTimer?.cancel();
    _timeoutTimer?.cancel();
    _connectionTimer = null;
    _timeoutTimer = null;
  }

  Future<void> retryChannel() async {
    if (_disposed || _currentChannel == null) return;
    _retryCount = 0;
    _connectionSeconds = 0;
    _hasEverPlayed = false;
    _isBuffering = true;

    _createPlayer();
    _safeNotify();

    await _configureMpvForChannel(_currentChannel!);
    _startConnectionTracking();
    _player!.open(Media(
      _currentChannel!.url,
      httpHeaders: _currentChannel!.httpHeaders.hasHeaders
          ? {
              if (_currentChannel!.httpHeaders.referrer != null)
                'Referer': _currentChannel!.httpHeaders.referrer!,
              if (_currentChannel!.httpHeaders.httpOrigin != null)
                'Origin': _currentChannel!.httpHeaders.httpOrigin!,
            }
          : null,
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
    _retryCount = 0;
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
