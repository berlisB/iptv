import 'package:iptv/core/catalog/curation_config.dart';
import 'package:iptv/features/home/domain/entities/channel_entity.dart';

/// Filtrage intelligent par audience + exclusions, et tri par pertinence.
///
/// Deux sélections :
///  - [reliable]  → mode "Sélection fiable" (peu, mais qui marchent) ;
///  - [explore]   → mode "Explorer" (plus large, badges côté UI).
///
/// Aucune dépendance UI : pure logique, testable unitairement.
class ChannelFilter {
  const ChannelFilter();

  /// True si la chaîne doit être écartée quel que soit le mode (langue/catégorie
  /// exclue par la [CurationConfig]). Repli heuristique sur le nom si aucun tag.
  bool isExcluded(ChannelEntity c) {
    if (CurationConfig.isExcludedLanguage(c.language)) return true;
    if (CurationConfig.isExcludedCategory(c.category)) return true;
    if (CurationConfig.isExcludedCategory(c.group)) return true;
    if (c.language.isEmpty &&
        CurationConfig.looksExcludedByName('${c.name} ${c.group}')) {
      return true;
    }
    return false;
  }

  /// Déduit l'audience quand elle n'est pas fournie (sources brutes).
  AudienceFit audienceOf(ChannelEntity c) {
    if (c.audienceFit != AudienceFit.other) return c.audienceFit;

    final lang = c.language.toLowerCase().trim();
    final country = c.country.toLowerCase().trim();

    if (CurationConfig.africaFrancophone.contains(country)) {
      return AudienceFit.africaFrancophone;
    }
    if (CurationConfig.francophoneLanguages.any((l) => lang == l)) {
      return AudienceFit.francophone;
    }
    if (CurationConfig.englishLanguages.any((l) => lang == l)) {
      return AudienceFit.englishUseful;
    }
    return AudienceFit.other;
  }

  /// Priorité effective (1=haute…3) dérivée de l'audience si non renseignée.
  int priorityOf(ChannelEntity c) {
    if (c.priority >= 1 && c.priority <= 3 && c.audienceFit != AudienceFit.other) {
      return c.priority;
    }
    switch (audienceOf(c)) {
      case AudienceFit.francophone:
      case AudienceFit.africaFrancophone:
        return 1;
      case AudienceFit.englishUseful:
        return 2;
      case AudienceFit.visualNoLanguage:
      case AudienceFit.other:
        return 3;
    }
  }

  /// Sélection fiable : exclut les langues hors-cible, garde ce qui est en
  /// ligne OU au-dessus du seuil de score, puis trie par priorité ↑ / score ↓.
  List<ChannelEntity> reliable(List<ChannelEntity> channels) {
    final kept = channels.where((c) {
      if (isExcluded(c)) return false;
      if (c.status == ChannelStatus.offline) return false;
      final passesScore =
          c.reliabilityScore >= CurationConfig.reliableThreshold;
      final isKnownGood = c.status == ChannelStatus.online || c.isOfficial;
      return passesScore || isKnownGood;
    }).toList();

    _sortByRelevance(kept);
    return kept;
  }

  /// Explorer : plus large — exclut seulement les langues hors-cible et les
  /// chaînes confirmées mortes. Le reste est montré (badges gérés par l'UI).
  List<ChannelEntity> explore(List<ChannelEntity> channels) {
    final kept =
        channels.where((c) => !isExcluded(c) && c.status != ChannelStatus.offline).toList();
    _sortByRelevance(kept);
    return kept;
  }

  void _sortByRelevance(List<ChannelEntity> list) {
    list.sort((a, b) {
      final pa = priorityOf(a);
      final pb = priorityOf(b);
      if (pa != pb) return pa.compareTo(pb);
      return b.reliabilityScore.compareTo(a.reliabilityScore);
    });
  }
}
