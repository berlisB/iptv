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

  // --- Failover multi-sources ---
  List<String> _sources = [];
  int _sourceIndex = 0;
  bool _exhausted = false; // toutes les sources testées sans succès

  bool _hasConnected = false; // mpv a commencé à recevoir des données
  bool _confirmedThisSession = false;

  /// Timeout "jamais connecté" : faible=12s, normal=18s, élevé=30s.
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

  /// Source actuellement testée (1-based) et total, pour l'UI.
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

  // Getters de compat UI
  int get retryCount => 0;
  bool get isRetrying => false;
  bool get hasExhaustedRetries => _exhausted;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  void _createPlayer() {
    _playingSub?.cancel();
    _bufferSub?.cancel();
    _widthSub?.cancel();
    _errorSub?.cancel();
    _player?.dispose();

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
      _safeNotify();
    });

    _bufferSub = _player!.stream.buffering.listen((buffering) {
      if (_disposed) return;
      _isBuffering = buffering;

      // Si mpv bufferise, c'est qu'il EST connecté et télécharge des données.
      if (buffering && !_hasConnected) {
        _hasConnected = true;
        _deadTimer?.cancel();
        _deadTimer = null;
      }

      // Auto-confirmation "fiable" : 30s de lecture fluide sans buffering.
      if (_hasEverPlayed && !_confirmedThisSession) {
        if (!buffering) {
          _confirmTimer?.cancel();
          _confirmTimer =
              Timer(const Duration(seconds: 30), _autoConfirmChannel);
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
        // Succès → on efface les strikes (decay) : la chaîne re-fonctionne.
        if (_currentChannel != null) {
          AppStorage.resetStrikes(_currentChannel!.id);
        }
        _cancelTimers();
        _safeNotify();
      }
    });

    // Échec DUR (403/404/codec/réseau) → on bascule sur la source suivante.
    _errorSub = _player!.stream.error.listen((err) {
      if (_disposed || _hasEverPlayed) return;
      debugPrint('[IPTV] Erreur sur source $currentSourceNumber: $err');
      if (!_tryNextSource()) _onAllSourcesFailed(hard: true);
    });
  }

  void _autoConfirmChannel() {
    if (_disposed || _currentChannel == null || _confirmedThisSession) return;
    _confirmedThisSession = true;
    AppStorage.confirmChannel(_currentChannel!.id);
    AppStorage.markConfirmedNow(_currentChannel!.id);
    debugPrint('[IPTV] Chaîne fiable confirmée: ${_currentChannel!.name}');
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

    _createPlayer();
    _safeNotify();

    await configureMpvForChannel(_player, channel);
    _startConnectionTracking();
    _openCurrentSource();
  }

  void _openCurrentSource() {
    if (_player == null || _currentChannel == null) return;
    final url = _sources[_sourceIndex];
    _player!.open(Media(url, httpHeaders: _buildHeaders(_currentChannel!)));
  }

  /// Passe à la source de secours suivante. Renvoie false si épuisé.
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

  /// Toutes les sources ont échoué. On ne pénalise (strike) que les échecs DURS.
  /// Un flux lent/injoignable (soft) n'est jamais banni : il peut juste ramer.
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

    // Timer "jamais connecté" : si mpv n'a établi AUCUNE connexion, on tente la
    // source suivante (sans strike : ce n'est peut-être qu'une chaîne lente).
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
    _connectionTimer = null;
    _deadTimer = null;
    _confirmTimer = null;
  }

  Future<void> retryChannel() async {
    if (_disposed || _currentChannel == null) return;
    await playChannel(_currentChannel!);
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
