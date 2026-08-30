import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:iptv/core/storage/app_storage.dart';
import 'package:iptv/features/home/domain/entities/channel_entity.dart';
import 'package:iptv/features/player/provider/mpv_config.dart';

class MiniPlayerProvider extends ChangeNotifier {
  MiniPlayerProvider() {
    // L'Android natif notifie les entrées/sorties de Picture-in-Picture.
    _pipChannel.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged') {
        _isInPip = call.arguments == true;
        _safeNotify();
      }
    });
  }

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
  StreamSubscription? _positionSub;
  Timer? _connectionTimer;
  Timer? _deadTimer;
  Timer? _confirmTimer;
  Timer? _stallTimer;

  List<String> _sources = [];
  int _sourceIndex = 0;
  bool _exhausted = false;

  bool _hasConnected = false;
  bool _confirmedThisSession = false;

  // Progression réelle de la lecture (seule preuve fiable de vie du flux :
  // stream.width n'est émis qu'au changement de résolution, jamais par frame).
  Duration _lastPosition = Duration.zero;
  DateTime _lastProgressAt = DateTime.now();
  int _consecutiveStalls = 0;

  // Debounce des erreurs mpv en cours de lecture.
  DateTime _errorWindowStart = DateTime.fromMillisecondsSinceEpoch(0);
  int _errorsInWindow = 0;
  DateTime? _lastErrorReopenAt;

  // Une seule pénalité de score par chaîne et par session.
  bool _penalizedThisSession = false;

  // Picture-in-Picture / cycle de vie.
  bool _isInPip = false;
  bool _pipEligible = false;
  bool _resumeOnForeground = false;
  DateTime? _backgroundedAt;

  /// Stall : position figée pendant cette durée alors que la lecture est
  /// censée tourner → reconnexion (puis failover si ça se répète).
  static const _stallTimeout = 20;

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
        // Reprise (ou démarrage) : on repart d'une horloge de progrès neuve
        // pour ne pas compter le temps de pause comme un stall.
        _lastProgressAt = DateTime.now();
      }
      _safeNotify();
    });

    _bufferSub = _player!.stream.buffering.listen((buffering) {
      if (_disposed) return;
      _isBuffering = buffering;

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

    // La position est la seule preuve continue de vie du flux : elle alimente
    // le moniteur de stall ET la détection de connexion réelle (des octets
    // sont décodés — contrairement à buffering=true qui précède tout octet).
    _positionSub = _player!.stream.position.listen((pos) {
      if (_disposed) return;
      if (pos != _lastPosition) {
        _lastPosition = pos;
        _lastProgressAt = DateTime.now();
        _consecutiveStalls = 0;
        if (!_hasConnected && pos > Duration.zero) _hasConnected = true;
      }
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
        _startStallMonitor();
        _safeNotify();
      }
    });

    _errorSub = _player!.stream.error.listen((err) {
      if (_disposed) return;
      debugPrint('[IPTV] Erreur mpv sur source $currentSourceNumber: $err');

      // Les erreurs de décodage (frame corrompue…) sont bénignes : mpv
      // récupère seul à la GOP suivante. N'agir que sur les erreurs réseau.
      if (!_isActionableError(err)) return;

      // Flux qui jouait : reconnexion débouncée, SANS toucher à
      // _hasEverPlayed (le remettre à false ouvrait la porte aux strikes et
      // au failover intempestif pendant le re-buffering).
      if (_hasEverPlayed) {
        final now = DateTime.now();
        if (now.difference(_errorWindowStart) > const Duration(seconds: 10)) {
          _errorWindowStart = now;
          _errorsInWindow = 0;
        }
        _errorsInWindow++;
        if (_errorsInWindow < 2) return;
        if (_lastErrorReopenAt != null &&
            now.difference(_lastErrorReopenAt!) <
                const Duration(seconds: 10)) {
          return;
        }
        _lastErrorReopenAt = now;
        debugPrint('[IPTV] Erreurs réseau répétées → reconnexion');
        _isBuffering = true;
        _safeNotify();
        _openCurrentSource();
        return;
      }

      if (!_tryNextSource()) _onAllSourcesFailed(hard: true);
    });
  }

  /// Erreur mpv qui mérite une action (réseau/flux). Le reste (décodage
  /// vidéo/audio, données corrompues ponctuelles) est loggé et ignoré.
  static bool _isActionableError(String err) {
    final e = err.toLowerCase();
    if (e.contains('decod') ||
        e.contains('invalid data') ||
        e.contains('corrupt') ||
        e.contains('packet')) {
      return false;
    }
    return true;
  }

  /// Moniteur de stall : vérifie toutes les 5 s que la position avance.
  /// Position figée > [_stallTimeout] s pendant une lecture active →
  /// reconnexion de la source courante, puis failover si ça se répète.
  void _startStallMonitor() {
    _stallTimer?.cancel();
    _lastProgressAt = DateTime.now();
    _stallTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_disposed || !_hasEverPlayed || !_isPlaying) return;
      final stalledFor = DateTime.now().difference(_lastProgressAt);
      if (stalledFor.inSeconds < _stallTimeout) return;

      _lastProgressAt = DateTime.now(); // pas de re-déclenchement immédiat
      _consecutiveStalls++;
      debugPrint('[IPTV] Stall: position figée ${stalledFor.inSeconds}s '
          '(occurrence $_consecutiveStalls)');

      if (_consecutiveStalls >= 2 && _tryNextSource()) return;

      _isBuffering = true;
      _safeNotify();
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
    _penalizedThisSession = false;
    _consecutiveStalls = 0;
    _errorsInWindow = 0;
    _lastErrorReopenAt = null;
    _lastPosition = Duration.zero;
    _connectionSeconds = 0;
    _isBuffering = true;

    // Reprise de session : on retrouve cette chaîne au prochain démarrage.
    if (channel.isLivestream) {
      AppStorage.setLastPlayedChannelId(channel.id);
    }
    _setPipEligible(true);

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
        .open(Media(url, httpHeaders: _currentChannel!.httpHeaders.toHttpMap()))
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
    // Pénalité DOUCE uniquement : une erreur mpv peut être un simple hiccup
    // réseau du téléphone. Les strikes (bannissement) sont réservés aux
    // verdicts fiables du probe HTTP (404/410). Max 1 pénalité par session.
    if (_currentChannel != null && !_penalizedThisSession) {
      _penalizedThisSession = true;
      if (hard) {
        AppStorage.recordSoftFail(_currentChannel!.id);
      } else {
        AppStorage.recordTimeout(_currentChannel!.id);
      }
      debugPrint('[IPTV] Sources épuisées (${hard ? 'erreur' : 'timeout'}) '
          '→ pénalité douce pour ${_currentChannel!.name}');
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
    _setPipEligible(false);
    await AppStorage.clearLastPlayedChannelId();
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

  /// True quand l'activité Android est en Picture-in-Picture : l'UI ne doit
  /// alors rendre que la vidéo (aucun contrôle dans la vignette).
  bool get isInPip => _isInPip;

  /// Signale au natif si un passage automatique en PiP a du sens (une lecture
  /// est en cours). Pilote `setAutoEnterEnabled` et `onUserLeaveHint`.
  void _setPipEligible(bool eligible) {
    if (_pipEligible == eligible) return;
    _pipEligible = eligible;
    _pipChannel
        .invokeMethod('setPipEligible', eligible)
        .catchError((_) => null);
  }

  // --- Cycle de vie de l'app ------------------------------------------------

  /// App en arrière-plan HORS PiP : on met en pause et on gèle le moniteur de
  /// stall (sinon il rouvrirait le flux en boucle en tâche de fond).
  void onAppBackground() {
    if (_disposed || _isInPip || !hasActivePlayer) return;
    _resumeOnForeground = _isPlaying;
    _backgroundedAt = DateTime.now();
    _stallTimer?.cancel();
    _player?.pause();
  }

  /// Retour au premier plan : reprise. Sur du live resté en pause > 30 s, le
  /// buffer est périmé → on rouvre au live edge plutôt que de jouer du différé.
  void onAppForeground() {
    if (_disposed || !hasActivePlayer || !_resumeOnForeground) return;
    _resumeOnForeground = false;
    final pausedFor = _backgroundedAt == null
        ? Duration.zero
        : DateTime.now().difference(_backgroundedAt!);
    _lastProgressAt = DateTime.now();
    if (_hasEverPlayed) _startStallMonitor();
    if ((_currentChannel?.isLivestream ?? false) &&
        pausedFor > const Duration(seconds: 30)) {
      debugPrint('[IPTV] Retour après ${pausedFor.inSeconds}s → live edge');
      _isBuffering = true;
      _safeNotify();
      _openCurrentSource();
    } else {
      _player?.play();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTimers();
    _playingSub?.cancel();
    _bufferSub?.cancel();
    _widthSub?.cancel();
    _errorSub?.cancel();
    _positionSub?.cancel();
    _playingSub = null;
    _bufferSub = null;
    _widthSub = null;
    _errorSub = null;
    _positionSub = null;
    try {
      _player?.dispose();
    } catch (_) {}
    _player = null;
    super.dispose();
  }
}
