import 'package:iptv/core/catalog/curation_config.dart';
import 'package:iptv/features/home/domain/entities/channel_entity.dart';

/// Convertit une entrée JSON du catalogue curé en [ChannelEntity].
///
/// Schéma JSON attendu (cf. assets/catalog/channels.json) :
/// ```json
/// { "id", "name", "logo", "streamUrl", "backupUrls"?, "tvgId"?,
///   "language", "country", "category", "audienceFit", "priority",
///   "sourceType", "status", "reliabilityScore"?, "lastCheckedAt"? }
/// ```
class CatalogChannelModel {
  CatalogChannelModel._();

  static ChannelEntity fromJson(Map<String, dynamic> j) {
    final category = (j['category'] as String?)?.trim() ?? '';
    return ChannelEntity(
      id: (j['id'] as String?)?.trim() ?? '',
      name: (j['name'] as String?)?.trim() ?? '',
      url: (j['streamUrl'] as String?)?.trim() ?? '',
      backupUrls: (j['backupUrls'] as List?)?.cast<String>() ?? const [],
      logoUrl: (j['logo'] as String?)?.trim() ?? '',
      // group = valeur brute ; on aligne sur la catégorie curée par défaut.
      group: category.isEmpty ? 'Autres' : category,
      category: category,
      language: (j['language'] as String?)?.trim() ?? '',
      country: (j['country'] as String?)?.trim() ?? '',
      tvgId: (j['tvgId'] as String?)?.trim() ?? '',
      audienceFit: _audience(j['audienceFit'] as String?),
      priority: (j['priority'] as num?)?.toInt() ?? 3,
      sourceType: _sourceType(j['sourceType'] as String?),
      status: _status(j['status'] as String?),
      reliabilityScore:
          (j['reliabilityScore'] as num?)?.toInt() ?? CurationConfig.initialScore,
      lastCheckedAt: j['lastCheckedAt'] != null
          ? DateTime.tryParse(j['lastCheckedAt'].toString())
          : null,
    );
  }

  static AudienceFit _audience(String? v) {
    switch (v) {
      case 'francophone':
        return AudienceFit.francophone;
      case 'africaFrancophone':
        return AudienceFit.africaFrancophone;
      case 'englishUseful':
        return AudienceFit.englishUseful;
      case 'visualNoLanguage':
        return AudienceFit.visualNoLanguage;
      default:
        return AudienceFit.other;
    }
  }

  static SourceType _sourceType(String? v) {
    switch (v) {
      case 'official_or_public':
        return SourceType.officialOrPublic;
      case 'community_verified':
        return SourceType.communityVerified;
      default:
        return SourceType.communityUnverified;
    }
  }

  static ChannelStatus _status(String? v) {
    switch (v) {
      case 'online':
        return ChannelStatus.online;
      case 'offline':
        return ChannelStatus.offline;
      default:
        return ChannelStatus.unknown;
    }
  }
}
