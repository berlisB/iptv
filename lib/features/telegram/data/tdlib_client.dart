/// Frontière entre la fonctionnalité Telegram et la bibliothèque native TDLib.
///
/// ⚠️ IMPLÉMENTATION INACTIVE — ce fichier est le bouchon.
///
/// Pourquoi : la lib native TDLib est servie par GitHub Packages Maven, qui
/// exige une authentification même pour un paquet public. Tant que `libtdjson`
/// figure dans pubspec.yaml, TOUT build Android échoue sur un
/// `401 Unauthorized`, y compris pour les gens qui ne se servent pas du canal
/// Telegram. Une fonctionnalité optionnelle ne doit pas bloquer la livraison
/// des autres.
///
/// Tout le reste de la fonctionnalité (indexation du canal, correspondance
/// TMDB, lecture progressive, interface) est indépendant de TDLib et reste
/// compilé : seul l'accès au réseau Telegram est neutralisé.
///
/// ─────────────────────────────────────────────────────────────────────────
/// POUR RÉACTIVER, deux gestes :
///
///   1. décommenter la dépendance dans pubspec.yaml :
///        libtdjson: ^0.3.0
///
///   2. remplacer ce fichier par l'implémentation réelle :
///        cd lib/features/telegram/data
///        mv tdlib_client.dart tdlib_client_stub.dart.disabled
///        mv tdlib_client_real.dart.disabled tdlib_client.dart
///
/// Puis `flutter pub get`. Il faudra alors un token GitHub avec le scope
/// `read:packages` dans ~/.gradle/gradle.properties (`gpr.user` / `gpr.key`) —
/// en CI GitHub Actions le GITHUB_TOKEN automatique suffit.
/// ─────────────────────────────────────────────────────────────────────────
library;

/// Vrai quand la bibliothèque native est embarquée dans ce build.
///
/// L'interface s'en sert pour afficher « indisponible dans cette version »
/// plutôt que de laisser croire à une panne réseau.
const bool tdlibAvailable = false;

/// Erreur remontée par TDLib, normalisée pour que le service ne dépende pas
/// du type d'exception d'un paquet tiers.
class TdlibException implements Exception {
  final String message;

  const TdlibException(this.message);

  @override
  String toString() => message;
}

/// Reçoit chaque objet poussé par TDLib (updates et réponses).
typedef TdlibUpdateHandler = void Function(Map<String, dynamic> update);

/// Ce que le service attend de TDLib, et rien de plus.
abstract interface class TdlibClient {
  /// Envoie une requête et attend sa réponse corrélée.
  /// Lève [TdlibException] si Telegram renvoie une erreur.
  Future<Map<String, dynamic>> send(Map<String, dynamic> request);

  /// Arrête la boucle de réception et libère le client natif.
  Future<void> stop();
}

/// Crée un client TDLib, ou retourne null si la bibliothèque n'est pas
/// embarquée dans ce build.
///
/// [parameters] est passé tel quel à `setTdlibParameters`.
TdlibClient? createTdlibClient({
  required Map<String, dynamic> parameters,
  required TdlibUpdateHandler onUpdate,
}) =>
    null;
