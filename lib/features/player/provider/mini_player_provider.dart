import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:iptv/core/storage/app_storage.dart';
import 'package:iptv/features/home/domain/entities/channel_entity.dart';
import 'package:iptv/features/player/provider/mpv_config.dart';

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
  StreamSubscription? _errorSub;
  Timer? _connectionTimer;
  Timer? _deadTimer;
  Timer? _confirmTimer;
  Timer? _stallTimer;

  List<String> _sources = [];
  int _sourceIndex = 0;
  bool _exhausted = false;

  bool _hasConnected = false;
  bool _confirmedThisSession = false;

  /// Détection de stall : si aucun frame reçu pendant cette durée alors qu'on
  /// jouait, on considère que le flux est mort et on tente une reconnexion.
  static const _stallTimeout = 15;

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

  int get currentSourceNumber => _sourceIndex + 1;
  int get totalSources => _sources.length;

  int get _deadTimeout =>
      _deadTimeoutByLevel[AppStorage.getBufferLevel().clamp(0, 2)];

  String get connectionStatus {
    if (_hasEverPlayed || _exhausted) return '';
    if (_hasConnected) return 'Chargement du flux... ${_connectionSeconds}s';
    if (totalSources > 1) {
      return 'Source $currentSourceNumber/$totalSources... ${_connectionSeconds}s';
    }
    if (_connectionSeconds > 3) return 'Connexion... ${_connectionSeconds}s';
    return '';
  }

  int get retryCount => 0;
  bool get isRetrying => false;
  bool get hasExhaustedRetries => _exhausted;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  /// Crée le player UNE SEULE FOIS. Les appels suivants le réutilisent.
  void _ensurePlayer() {
    if (_player != null) return;

    final level = AppStorage.getBufferLevel().clamp(0, 2);
    _player = Player(
      configuration: PlayerConfiguration(
        bufferSize: bufferPresets[level][0] * 1024 * 1024,
        logLevel: MPVLogLevel.warn,
      ),
    );
    _videoController = VideoController(_player!);

    _playingSub = _player!.stream.playing.listen((playing) {
      if (_disposed) return;
      _isPlaying = playing;

      if (playing) {
        // Lecture confirmée → on relance le stall detector.
        _restartStallDetector();
      } else {
        _stallTimer?.cancel();
      }

      _safeNotify();
    });

    _bufferSub = _player!.stream.buffering.listen((buffering) {
      if (_disposed) return;
      _isBuffering = buffering;

      if (buffering && !_hasConnected) {
        _hasConnected = true;
        _deadTimer?.cancel();
        _deadTimer = null;
      }

      if (_hasEverPlayed && !_confirmedThisSession) {
        if (!buffering) {
          _confirmTimer?.cancel();
          _confirmTimer =
              Timer(const Duration(seconds: 20), _autoConfirmChannel);
        } else {
          _confirmTimer?.cancel();
          _confirmTimer = null;
        }
      }
      _safeNotify();
    });

    _widthSub = _player!.stream.width.listen((width) {
      if (_disposed) return;
      if (width != null && width > 0 && !_hasEverPlayed) {
        debugPrint('[IPTV] Frames reçues (${width}px) sur source '
            '$currentSourceNumber/$totalSources');
        _hasEverPlayed = true;
        _hasConnected = true;
        _exhausted = false;
        if (_currentChannel != null) {
          AppStorage.resetStrikes(_currentChannel!.id);
        }
        _cancelTimers();
        _restartStallDetector();
        _safeNotify();
      } else if (width != null && width > 0) {
        // Flux déjà en cours → reset du stall timer (on reçoit des frames).
        _restartStallDetector();
      }
    });

    _errorSub = _player!.stream.error.listen((err) {
      if (_disposed) return;
      debugPrint('[IPTV] Erreur sur source $currentSourceNumber: $err');

      // Si on jouait déjà, on tente une reconnexion sur la même source.
      if (_hasEverPlayed) {
        debugPrint('[IPTV] Stall détecté via erreur → reconnexion');
        _hasEverPlayed = false;
        _hasConnected = false;
        _connectionSeconds = 0;
        _isBuffering = true;
        _safeNotify();
        _startConnectionTracking();
        _openCurrentSource();
        return;
      }

      if (!_tryNextSource()) _onAllSourcesFailed(hard: true);
    });
  }

  /// (Re)démarre le timer de détection de stall.
  void _restartStallDetector() {
    _stallTimer?.cancel();
    _stallTimer = Timer(const Duration(seconds: _stallTimeout), () {
      if (_disposed || !_hasEverPlayed) return;
      debugPrint('[IPTV] Stall: aucun frame reçu pendant ${_stallTimeout}s '
          '→ reconnexion sur même source');
      _hasEverPlayed = false;
      _hasConnected = false;
      _connectionSeconds = 0;
      _isBuffering = true;
      _safeNotify();
      _startConnectionTracking();
      _openCurrentSource();
    });
  }

  void _autoConfirmChannel() {
    if (_disposed || _currentChannel == null || _confirmedThisSession) return;
    _confirmedThisSession = true;
    // 20 s de lecture sans coupure = meilleur signal de fiabilité qui soit :
    // il alimente le score persistant (source unique de vérité).
    AppStorage.recordSuccess(_currentChannel!.id);
    debugPrint('[IPTV] Lecture stable, score récompensé: '
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
    debugPrint('[IPTV] playChannel: ${channel.name} '
        '(${channel.sourceCount} source(s))');

    _currentChannel = channel;
    _sources = channel.allUrls;
    _sourceIndex = 0;
    _exhausted = false;
    _isMiniMode = false;
    _hasEverPlayed = false;
    _hasConnected = false;
    _confirmedThisSession = false;
    _connectionSeconds = 0;
    _isBuffering = true;

    _ensurePlayer();
    _cancelTimers();
    _safeNotify();

    await configureMpvForChannel(_player, channel);
    _startConnectionTracking();
    _openCurrentSource();
  }

  void _openCurrentSource() {
    if (_player == null || _currentChannel == null) return;
    final url = _sources[_sourceIndex];
    _player!
        .open(Media(url, httpHeaders: _buildHeaders(_currentChannel!)))
        .catchError((e) {
      if (!_disposed) {
        debugPrint('[IPTV] open() échoué: $e');
        if (!_hasEverPlayed) {
          if (!_tryNextSource()) _onAllSourcesFailed(hard: true);
        }
      }
    });
  }

  bool _tryNextSource() {
    if (_sourceIndex + 1 >= _sources.length) return false;
    _sourceIndex++;
    _hasConnected = false;
    _connectionSeconds = 0;
    _isBuffering = true;
    debugPrint('[IPTV] Failover → source $currentSourceNumber/$totalSources');
    _safeNotify();
    _startConnectionTracking();
    _openCurrentSource();
    return true;
  }

  void _onAllSourcesFailed({required bool hard}) {
    _exhausted = true;
    if (hard && _currentChannel != null) {
      AppStorage.addStrike(_currentChannel!.id);
      debugPrint('[IPTV] Échec dur épuisé → strike pour ${_currentChannel!.name}');
    }
    _safeNotify();
  }

  void _startConnectionTracking() {
    _connectionTimer?.cancel();
    _deadTimer?.cancel();

    _connectionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || _hasEverPlayed) {
        _connectionTimer?.cancel();
        return;
      }
      _connectionSeconds++;
      _safeNotify();
    });

    final timeout = _deadTimeout;
    _deadTimer = Timer(Duration(seconds: timeout), () {
      if (_disposed || _hasEverPlayed || _hasConnected) return;
      debugPrint('[IPTV] Aucune connexion après ${timeout}s sur '
          'source $currentSourceNumber');
      if (!_tryNextSource()) _onAllSourcesFailed(hard: false);
    });
  }

  void _cancelTimers() {
    _connectionTimer?.cancel();
    _deadTimer?.cancel();
    _confirmTimer?.cancel();
    _stallTimer?.cancel();
    _connectionTimer = null;
    _deadTimer = null;
    _confirmTimer = null;
    _stallTimer = null;
  }

  Future<void> retryChannel() async {
    if (_disposed || _currentChannel == null) return;
    final ch = _currentChannel!;

    // Réutilise le player existant : on ouvre juste la même source à nouveau.
    _hasEverPlayed = false;
    _hasConnected = false;
    _exhausted = false;
    _confirmedThisSession = false;
    _connectionSeconds = 0;
    _isBuffering = true;

    _cancelTimers();
    _safeNotify();

    await configureMpvForChannel(_player, ch);
    _startConnectionTracking();
    _openCurrentSource();
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
    _position = Offset(_position.dx + delta.dx, _position.dy + delta.dy);
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
    _sources = [];
    _sourceIndex = 0;
    _exhausted = false;
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
    _errorSub?.cancel();
    _playingSub = null;
    _bufferSub = null;
    _widthSub = null;
    _errorSub = null;
    try {
      _player?.dispose();
    } catch (_) {}
    _player = null;
    super.dispose();
  }
}
