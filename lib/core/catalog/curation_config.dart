import 'package:iptv/features/home/domain/entities/channel_entity.dart';

/// Configuration de curation — **point unique d'édition** des règles métier.
///
/// Tu peux modifier librement :
///  - les langues / catégories exclues par défaut ;
///  - les poids du score de fiabilité ;
///  - le seuil sous lequel une chaîne est masquée en "Sélection fiable" ;
///  - les langues/pays qui définissent l'audience (francophone, anglophone…).
///
/// Rien d'autre dans le code ne devrait coder en dur ces valeurs : tout passe
/// par ici. (Plus tard, ce fichier pourra être alimenté par un JSON distant.)
class CurationConfig {
  CurationConfig._();

  // --- Exclusions par défaut -------------------------------------------------

  /// Langues exclues par défaut (codes ISO 639 + libellés courants tolérés).
  /// La comparaison est insensible à la casse et par "contient".
  static const Set<String> excludedLanguages = {
    'ar', 'ara', 'arabic', 'arabe',
    'id', 'ind', 'indonesian', 'indonesien', 'indonésien',
    'hi', 'hin', 'hindi',
    'tr', 'tur', 'turkish', 'turc',
    'ru', 'rus', 'russian', 'russe',
    'fa', 'fas', 'per', 'persian', 'persan', 'farsi',
    'ur', 'urd', 'urdu',
  };

  /// Catégories exclues par défaut (comparaison insensible à la casse).
  /// NB : l'adulte n'est PAS exclu ici — il est masqué par le toggle
  /// « Contenu adulte » des Réglages (_applyFilters), pour rester activable.
  static const Set<String> excludedCategories = {};

  /// Marqueurs de nom/groupe trahissant une langue exclue quand le tag
  /// `tvg-language` est absent (fréquent sur les sources brutes).
  static const Set<String> excludedNameMarkers = {
    'arabic', 'arabia', 'بث', 'قناة', // arabe
    'indonesia', 'tvri', // indonésien
    'hindi', 'bharat', // hindi
    'türk', 'turk', // turc ('kanal' retiré : trop générique, exclut Kanal D…)
    'россия', 'russia', 'тв', // russe
    'iran', 'irib', 'persian', // persan
  };

  // --- Score de fiabilité (0..100) -------------------------------------------

  static const int initialScore = 60;
  static const int maxScore = 100;
  static const int minScore = 0;

  /// Succès de lecture / probe OK → on récompense.
  static const int rewardSuccess = 15;

  /// Échec "mou" (injoignable, lent, erreur réseau transitoire) → pénalité douce.
  static const int penaltySoftFail = 10;

  /// Timeout → pénalité moyenne.
  static const int penaltyTimeout = 15;

  /// Échec "dur" (HTTP 404/410 avéré) → forte pénalité, mais il en faut
  /// deux (60 - 2×25 < 35) pour passer sous le seuil "Sélection fiable" :
  /// un seul faux positif ne masque plus une chaîne.
  static const int penaltyHardFail = 25;

  /// Sous ce score, une chaîne est masquée en mode "Sélection fiable".
  /// (Elle reste visible en "Explorer" avec un badge.)
  static const int reliableThreshold = 35;

  // --- Définition de l'audience ----------------------------------------------

  static const Set<String> francophoneLanguages = {
    'fr', 'fra', 'fre', 'french', 'francais', 'français',
  };

  static const Set<String> englishLanguages = {
    'en', 'eng', 'english', 'anglais',
  };

  /// Pays d'Afrique francophone (codes ISO + libellés) pour [AudienceFit].
  static const Set<String> africaFrancophone = {
    'sn', 'ci', 'cm', 'ml', 'bf', 'ne', 'td', 'ga', 'cg', 'cd',
    'bj', 'tg', 'gn', 'mg', 'rw', 'dj', 'km', 'mr', 'bi',
    'senegal', 'sénégal', "côte d'ivoire", "cote d'ivoire", 'cameroun',
    'mali', 'burkina faso', 'niger', 'tchad', 'gabon', 'congo',
    'bénin', 'benin', 'togo', 'guinée', 'guinee', 'madagascar', 'rwanda',
  };

  // --- Helpers ---------------------------------------------------------------

  /// True si la langue (tag ou libellé) est dans la liste d'exclusion.
  static bool isExcludedLanguage(String language) {
    final l = language.toLowerCase().trim();
    if (l.isEmpty) return false;
    if (excludedLanguages.contains(l)) return true;
    return excludedLanguages.any((e) => l == e || l.contains(e));
  }

  /// True si la catégorie/groupe est exclue.
  static bool isExcludedCategory(String category) {
    final c = category.toLowerCase().trim();
    if (c.isEmpty) return false;
    return excludedCategories.any((e) => c.contains(e));
  }

  /// Heuristique de repli sur le nom/groupe quand aucun tag langue n'existe.
  static bool looksExcludedByName(String text) {
    final t = text.toLowerCase();
    return excludedNameMarkers.any((m) => t.contains(m));
  }

  /// Clampe un score dans [minScore, maxScore].
  static int clampScore(int v) => v.clamp(minScore, maxScore);
}
