/// Accès Telegram via TDLib, embarqué dans l'app — aucun serveur.
///
/// Pourquoi TDLib et pas l'API Bot : `getFile` de l'API Bot plafonne les
/// téléchargements à 20 Mo, alors qu'un film pèse plusieurs Go. TDLib parle le
/// protocole client (MTProto) et lit un fichier par offset, ce qui permet la
/// lecture progressive — c'est le mécanisme des clients Telegram officiels.
///
/// Conséquence assumée de ce choix : chaque utilisateur se connecte avec SON
/// compte Telegram et doit voir le canal. En échange, les fichiers transitent
/// directement du CDN Telegram vers l'appareil : aucune bande passante à notre
/// charge, quel que soit le nombre d'utilisateurs.
///
/// Configuration requise (https://my.telegram.org, onglet API development) :
///   flutter run --dart-define=TELEGRAM_API_ID=123456 \
///               --dart-define=TELEGRAM_API_HASH=abcdef...
///
/// ⚠️ Build Android : la lib native est servie par GitHub Packages Maven, qui
/// exige une authentification même en public. Renseigner une fois pour toutes
/// dans ~/.gradle/gradle.properties :
///   `gpr.user=<login github>`
///   `gpr.key=<token github avec le scope read:packages>`
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:libtdjson/libtdjson.dart' as td;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// État d'authentification, réduit à ce dont l'UI a besoin pour décider quoi
/// afficher. Les états TDLib intermédiaires sont absorbés par le service.
enum TelegramAuthState {
  /// TDLib n'est pas encore démarré.
  idle,

  /// Démarrage en cours, état réel pas encore connu.
  connecting,

  /// Il faut un numéro de téléphone.
  waitPhone,

  /// Il faut le code reçu par Telegram.
  waitCode,

  /// Il faut le mot de passe de vérification en deux étapes.
  waitPassword,

  /// Connecté : les requêtes sont possibles.
  ready,

  /// Déconnexion en cours ou terminée.
  loggedOut,

  /// Échec bloquant (identifiants d'API absents, lib native manquante…).
  failed,
}

/// Progression d'un téléchargement de fichier Telegram.
class TelegramDownload {
  /// Chemin local du fichier, vide tant que TDLib n'a rien écrit.
  final String path;

  /// Octets contigus disponibles depuis le début — c'est cette valeur, et non
  /// `downloadedSize`, qui autorise la lecture : un préfixe contigu est
  /// lisible, des morceaux épars ne le sont pas.
  final int downloadedPrefixSize;

  /// Taille totale attendue, 0 si Telegram ne l'annonce pas.
  final int expectedSize;

  final bool isCompleted;

  const TelegramDownload({
    this.path = '',
    this.downloadedPrefixSize = 0,
    this.expectedSize = 0,
    this.isCompleted = false,
  });

  double get progress =>
      expectedSize > 0 ? downloadedPrefixSize / expectedSize : 0;

  bool get isPlayable => path.isNotEmpty && downloadedPrefixSize > 0;
}

class TelegramService {
  TelegramService._();

  static final TelegramService instance = TelegramService._();

  /// Identifiants d'API, injectés à la compilation comme la clé TMDB.
  static const int _apiId = int.fromEnvironment('TELEGRAM_API_ID');
  static const String _apiHash =
      String.fromEnvironment('TELEGRAM_API_HASH');

  /// Vrai si l'app a été compilée avec des identifiants Telegram.
  static bool get isConfigured => _apiId != 0 && _apiHash.isNotEmpty;

  td.Service? _service;

  final _authController =
      StreamController<TelegramAuthState>.broadcast();
  var _authState = TelegramAuthState.idle;

  /// Dernier état connu de chaque fichier suivi, indexé par file_id.
  final _downloads = <int, TelegramDownload>{};
  final _downloadControllers =
      <int, StreamController<TelegramDownload>>{};

  Stream<TelegramAuthState> get authStates => _authController.stream;
  TelegramAuthState get authState => _authState;
  bool get isReady => _authState == TelegramAuthState.ready;

  /// Message d'erreur de la dernière opération échouée, pour affichage.
  String lastError = '';

  // -------------------------------------------------------------------------
  // Cycle de vie
  // -------------------------------------------------------------------------

  /// Démarre TDLib. Idempotent : un second appel ne recrée pas le client.
  Future<void> start() async {
    if (_service != null) return;
    if (!isConfigured) {
      lastError = 'Identifiants Telegram absents : compilez avec '
          '--dart-define=TELEGRAM_API_ID et --dart-define=TELEGRAM_API_HASH';
      _emit(TelegramAuthState.failed);
      return;
    }

    _emit(TelegramAuthState.connecting);
    try {
      final support = await getApplicationSupportDirectory();
      final dbDir = p.join(support.path, 'tdlib');
      // Les fichiers vidéo vivent dans le cache : ils sont volumineux et
      // reconstructibles, donc éligibles à l'éviction par l'OS plutôt que
      // comptés comme données utilisateur à sauvegarder.
      final cache = await getApplicationCacheDirectory();
      final filesDir = p.join(cache.path, 'tdlib_files');
      await Directory(dbDir).create(recursive: true);
      await Directory(filesDir).create(recursive: true);

      _service = td.Service(
        // Verbosité 1 = erreurs seulement. TDLib est très bavard par défaut
        // et noierait les logs de l'app.
        newVerbosityLevel: 1,
        tdlibParameters: {
          'api_id': _apiId,
          'api_hash': _apiHash,
          'database_directory': dbDir,
          'files_directory': filesDir,
          'use_file_database': true,
          'use_chat_info_database': true,
          'use_message_database': true,
          'use_secret_chats': false,
          'system_language_code': Platform.localeName.split('_').first,
          'device_model': _deviceModel,
          'application_version': '1.0.0',
        },
        afterReceive: _onUpdate,
        onReceiveError: (e) => debugPrint('[TG] erreur: ${e.message}'),
        onStreamError: (e) => debugPrint('[TG] flux: $e'),
      );
    } catch (e) {
      // Cas le plus probable : la lib native n'est pas embarquée dans le build
      // (token GitHub Packages manquant côté Android).
      lastError = 'TDLib indisponible : $e';
      _emit(TelegramAuthState.failed);
    }
  }

  static String get _deviceModel {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    return 'Flutter';
  }

  Future<void> dispose() async {
    for (final c in _downloadControllers.values) {
      await c.close();
    }
    _downloadControllers.clear();
    await _service?.stop();
    _service = null;
    _emit(TelegramAuthState.idle);
  }

  void _emit(TelegramAuthState state) {
    if (_authState == state) return;
    _authState = state;
    if (!_authController.isClosed) _authController.add(state);
    debugPrint('[TG] état = $state');
  }

  // -------------------------------------------------------------------------
  // Réception des updates
  // -------------------------------------------------------------------------

  void _onUpdate(Map<String, dynamic> obj) {
    switch (obj['@type']) {
      case 'updateAuthorizationState':
        _onAuthState(obj['authorization_state'] as Map<String, dynamic>?);
        break;
      case 'updateFile':
        _onFileUpdate(obj['file'] as Map<String, dynamic>?);
        break;
    }
  }

  void _onAuthState(Map<String, dynamic>? state) {
    switch (state?['@type']) {
      // setTdlibParameters est envoyé par la couche libtdjson elle-même.
      case 'authorizationStateWaitPhoneNumber':
        _emit(TelegramAuthState.waitPhone);
        break;
      case 'authorizationStateWaitCode':
        _emit(TelegramAuthState.waitCode);
        break;
      case 'authorizationStateWaitPassword':
        _emit(TelegramAuthState.waitPassword);
        break;
      case 'authorizationStateReady':
        _emit(TelegramAuthState.ready);
        break;
      case 'authorizationStateLoggingOut':
      case 'authorizationStateClosing':
      case 'authorizationStateClosed':
        _emit(TelegramAuthState.loggedOut);
        break;
    }
  }

  void _onFileUpdate(Map<String, dynamic>? file) {
    if (file == null) return;
    final id = file['id'] as int?;
    if (id == null) return;
    final local = (file['local'] as Map<String, dynamic>?) ?? const {};
    final update = TelegramDownload(
      path: (local['path'] as String?) ?? '',
      downloadedPrefixSize: (local['downloaded_prefix_size'] as int?) ?? 0,
      expectedSize: (file['expected_size'] as int?) ??
          (file['size'] as int?) ??
          0,
      isCompleted: (local['is_downloading_completed'] as bool?) ?? false,
    );
    _downloads[id] = update;
    _downloadControllers[id]?.add(update);
  }

  // -------------------------------------------------------------------------
  // Authentification
  // -------------------------------------------------------------------------

  Future<bool> submitPhone(String phone) =>
      _call({'@type': 'setAuthenticationPhoneNumber', 'phone_number': phone});

  Future<bool> submitCode(String code) =>
      _call({'@type': 'checkAuthenticationCode', 'code': code});

  Future<bool> submitPassword(String password) =>
      _call({'@type': 'checkAuthenticationPassword', 'password': password});

  Future<bool> logOut() => _call({'@type': 'logOut'});

  /// Envoie une requête sans exploiter le résultat ; retourne false et remplit
  /// [lastError] en cas d'échec, pour que l'UI affiche le motif exact renvoyé
  /// par Telegram (« PHONE_CODE_INVALID », « PASSWORD_HASH_INVALID »…).
  Future<bool> _call(Map<String, dynamic> request) async {
    final service = _service;
    if (service == null) {
      lastError = 'TDLib non démarré';
      return false;
    }
    try {
      await service.sendSync(request);
      lastError = '';
      return true;
    } catch (e) {
      lastError = _readableError(e);
      debugPrint('[TG] ${request['@type']} → $lastError');
      return false;
    }
  }

  /// Traduit les codes d'erreur Telegram les plus fréquents.
  static String _readableError(Object e) {
    final raw = e is td.Error ? e.message : '$e';
    switch (raw) {
      case 'PHONE_NUMBER_INVALID':
        return 'Numéro de téléphone invalide.';
      case 'PHONE_CODE_INVALID':
        return 'Code incorrect.';
      case 'PHONE_CODE_EXPIRED':
        return 'Code expiré, redemandez-en un.';
      case 'PASSWORD_HASH_INVALID':
        return 'Mot de passe incorrect.';
      case 'USERNAME_NOT_OCCUPIED':
      case 'USERNAME_INVALID':
        return 'Canal introuvable : vérifiez son identifiant.';
      case 'CHANNEL_PRIVATE':
        return 'Canal privé : rejoignez-le avec ce compte Telegram.';
      default:
        if (raw.startsWith('FLOOD_WAIT_')) {
          final s = raw.substring('FLOOD_WAIT_'.length);
          return 'Trop de requêtes, réessayez dans $s secondes.';
        }
        return raw;
    }
  }

  // -------------------------------------------------------------------------
  // Requêtes
  // -------------------------------------------------------------------------

  /// Requête typée ; retourne null et remplit [lastError] en cas d'échec.
  Future<Map<String, dynamic>?> request(Map<String, dynamic> req) async {
    final service = _service;
    if (service == null) {
      lastError = 'TDLib non démarré';
      return null;
    }
    try {
      final r = await service.sendSync(req);
      lastError = '';
      return r;
    } catch (e) {
      lastError = _readableError(e);
      debugPrint('[TG] ${req['@type']} → $lastError');
      return null;
    }
  }

  /// Résout un canal depuis son identifiant public (@nom ou nom).
  /// Retourne le chat_id, ou null si introuvable/inaccessible.
  Future<int?> resolveChannel(String username) async {
    final clean = username.trim().replaceFirst(RegExp(r'^@'), '');
    if (clean.isEmpty) return null;
    final chat = await request({
      '@type': 'searchPublicChat',
      'username': clean,
    });
    return chat?['id'] as int?;
  }

  // -------------------------------------------------------------------------
  // Téléchargement
  // -------------------------------------------------------------------------

  /// Suit la progression d'un fichier. Le flux réémet le dernier état connu
  /// dès l'abonnement, pour qu'un écran rouvert n'attende pas le prochain
  /// update TDLib avant d'afficher quelque chose.
  Stream<TelegramDownload> watchFile(int fileId) {
    final controller = _downloadControllers.putIfAbsent(
      fileId,
      () => StreamController<TelegramDownload>.broadcast(),
    );
    final known = _downloads[fileId];
    if (known != null) {
      scheduleMicrotask(() {
        if (!controller.isClosed) controller.add(known);
      });
    }
    return controller.stream;
  }

  /// Démarre (ou reprend) le téléchargement d'un fichier.
  ///
  /// `limit: 0` demande le fichier entier ; TDLib écrit séquentiellement
  /// depuis `offset`, ce qui rend le préfixe lisible au fur et à mesure.
  Future<bool> startDownload(int fileId, {int offset = 0}) => _call({
        '@type': 'downloadFile',
        'file_id': fileId,
        // 32 = priorité maximale : c'est le fichier que l'utilisateur regarde.
        'priority': 32,
        'offset': offset,
        'limit': 0,
        'synchronous': false,
      });

  Future<bool> cancelDownload(int fileId) =>
      _call({'@type': 'cancelDownloadFile', 'file_id': fileId, 'only_if_pending': false});

  /// Libère l'espace disque pris par un fichier téléchargé.
  Future<bool> deleteFile(int fileId) =>
      _call({'@type': 'deleteFile', 'file_id': fileId});

  TelegramDownload downloadStateOf(int fileId) =>
      _downloads[fileId] ?? const TelegramDownload();
}
