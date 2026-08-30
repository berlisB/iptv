import 'package:equatable/equatable.dart';

class ChannelHttpHeaders {
  final String? referrer;
  final String? userAgent;
  final String? httpOrigin;
  final bool ignoreSSL;

  const ChannelHttpHeaders({
    this.referrer,
    this.userAgent,
    this.httpOrigin,
    this.ignoreSSL = false,
  });

  bool get hasHeaders =>
      referrer != null || userAgent != null || httpOrigin != null;

  /// Headers HTTP à envoyer pour ce flux — LE point unique de construction,
  /// partagé par le player (Media) et le probe (StreamValidator) pour que
  /// les deux voient le serveur de la même façon.
  Map<String, String>? toHttpMap() {
    if (!hasHeaders) return null;
    return {
      'Referer': ?referrer,
      'Origin': ?httpOrigin,
      'User-Agent': ?userAgent,
    };
  }
}

enum MediaType { livestream, movie }

/// À quel public la chaîne est destinée — pilote la priorité d'affichage.
/// [other] = non classé (sera déduit ou rétrogradé).
enum AudienceFit {
  francophone,
  africaFrancophone,
  englishUseful,
  visualNoLanguage,
  other,
}

/// Provenance de la chaîne — pilote la confiance par défaut.
enum SourceType { officialOrPublic, communityVerified, communityUnverified }

/// État de disponibilité connu du flux (mis à jour par le StreamValidator).
enum ChannelStatus { online, offline, unknown }

class ChannelEntity extends Equatable {
  final String id;
  final String name;
  final String url;

  /// URLs de secours (même chaîne, autres sources) pour le failover automatique.
  final List<String> backupUrls;

  final String logoUrl;
  final String group;
  final String language;
  final String country;

  /// Identifiant EPG d'origine (tvg-id) conservé pour mapper le guide des programmes.
  final String tvgId;

  /// Qualité déclarée par la source (ex: "1080p", "720p"), vide si inconnue.
  final String quality;

  final MediaType mediaType;
  final ChannelHttpHeaders httpHeaders;

  final bool isGeoBlocked;

  // --- Métadonnées de curation (catalogue propre / backend-ready) ---

  /// Public visé. Pilote la priorité d'affichage et le filtrage par audience.
  final AudienceFit audienceFit;

  /// Priorité éditoriale : 1 = francophone/utile, 2 = anglophone utile,
  /// 3 = visuel international. Plus c'est bas, plus la chaîne remonte.
  final int priority;

  /// Catégorie orientée utilisateur (ex: "Infos", "Documentaires").
  /// Distincte de [group] qui reste la valeur brute de la source.
  final String category;

  /// Provenance : officiel/public vs communautaire (vérifié ou non).
  final SourceType sourceType;

  /// Disponibilité connue, mise à jour par le StreamValidator.
  final ChannelStatus status;

  /// Score de fiabilité 0..100. Snapshot ; la source de vérité vit dans le
  /// stockage (decay au fil des succès/échecs).
  final int reliabilityScore;

  /// Dernière vérification du flux (null = jamais testé).
  final DateTime? lastCheckedAt;

  const ChannelEntity({
    required this.id,
    required this.name,
    required this.url,
    this.backupUrls = const [],
    this.logoUrl = '',
    this.group = 'Autres',
    this.language = '',
    this.country = '',
    this.tvgId = '',
    this.quality = '',
    this.mediaType = MediaType.livestream,
    this.httpHeaders = const ChannelHttpHeaders(),
    this.isGeoBlocked = false,
    this.audienceFit = AudienceFit.other,
    this.priority = 3,
    this.category = '',
    this.sourceType = SourceType.communityUnverified,
    this.status = ChannelStatus.unknown,
    this.reliabilityScore = 50,
    this.lastCheckedAt,
  });

  /// True si la chaîne provient d'une source officielle/publique (la + sûre).
  bool get isOfficial => sourceType == SourceType.officialOrPublic;

  /// True si le flux n'a jamais été validé (badge "Non vérifiée" en Explorer).
  bool get isUnverified => status == ChannelStatus.unknown;

  bool get isLivestream => mediaType == MediaType.livestream;

  /// Toutes les URLs jouables (principale + secours) dans l'ordre de tentative.
  List<String> get allUrls => [url, ...backupUrls];

  /// Nombre total de sources disponibles pour cette chaîne.
  int get sourceCount => 1 + backupUrls.length;

  bool get isAdult {
    final g = group.toLowerCase();
    final n = name.toLowerCase();
    return g.contains('xxx') ||
        g.contains('adult') ||
        g.contains('+18') ||
        n.contains('xxx') ||
        n.contains('adult') ||
        n.contains('+18');
  }

  /// Nom nettoyé des marqueurs (géo-bloqué, not 24/7...).
  String get cleanName => name
      .replaceAll(RegExp(r'\[Geo-blocked\]', caseSensitive: false), '')
      .replaceAll('Ⓖ', '')
      .replaceAll(RegExp(r'\[Not 24/7\]', caseSensitive: false), '')
      .replaceAll('Ⓢ', '')
      .replaceAll('Ⓣ', '')
      .replaceAll('Ⓨ', '')
      .replaceAll('Ⓓ', '')
      .trim();

  ChannelEntity copyWith({
    String? id,
    String? name,
    String? url,
    List<String>? backupUrls,
    String? logoUrl,
    String? group,
    String? language,
    String? country,
    String? tvgId,
    String? quality,
    MediaType? mediaType,
    ChannelHttpHeaders? httpHeaders,
    bool? isGeoBlocked,
    AudienceFit? audienceFit,
    int? priority,
    String? category,
    SourceType? sourceType,
    ChannelStatus? status,
    int? reliabilityScore,
    DateTime? lastCheckedAt,
  }) {
    return ChannelEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      backupUrls: backupUrls ?? this.backupUrls,
      logoUrl: logoUrl ?? this.logoUrl,
      group: group ?? this.group,
      language: language ?? this.language,
      country: country ?? this.country,
      tvgId: tvgId ?? this.tvgId,
      quality: quality ?? this.quality,
      mediaType: mediaType ?? this.mediaType,
      httpHeaders: httpHeaders ?? this.httpHeaders,
      isGeoBlocked: isGeoBlocked ?? this.isGeoBlocked,
      audienceFit: audienceFit ?? this.audienceFit,
      priority: priority ?? this.priority,
      category: category ?? this.category,
      sourceType: sourceType ?? this.sourceType,
      status: status ?? this.status,
      reliabilityScore: reliabilityScore ?? this.reliabilityScore,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    );
  }

  @override
  List<Object?> get props =>
      [id, name, url, backupUrls, logoUrl, group, language, country, mediaType];
}
