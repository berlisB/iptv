import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
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
    // Clean up old player if any
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
      // Don't use playing to set _hasEverPlayed - media_kit fires
      // playing:true immediately on open() before any video is decoded.
      // We rely on the width stream for actual video confirmation.
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

  Future<void> playChannel(ChannelEntity channel) async {
    if (_disposed) return;

    debugPrint('[IPTV] playChannel: ${channel.name} -> ${channel.url}');

    _currentChannel = channel;
    _isMiniMode = false;
    _hasEverPlayed = false;
    _retryCount = 0;
    _connectionSeconds = 0;
    _isBuffering = true;

    // Always create a fresh player to avoid stuck states
    _createPlayer();
    _safeNotify();

    _startConnectionTracking();
    _player!.open(Media(channel.url));
  }

  void _startConnectionTracking() {
    _cancelTimers();

    _connectionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || _hasEverPlayed) {
        _cancelTimers();
        return;
      }
      _connectionSeconds++;
      debugPrint('[IPTV] Connecting... ${_connectionSeconds}s (retry: $_retryCount)');
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

      // Recreate player entirely to avoid stuck stop()
      _createPlayer();
      _player!.open(Media(_currentChannel!.url));

      _timeoutTimer?.cancel();
      _timeoutTimer = Timer(Duration(seconds: _timeoutSeconds), () {
        _onConnectionTimeout();
      });
    } else {
      debugPrint('[IPTV] All retries exhausted');
      _cancelTimers();
      _isBuffering = false;
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

    _startConnectionTracking();
    _player!.open(Media(_currentChannel!.url));
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
