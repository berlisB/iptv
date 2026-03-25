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
}

enum MediaType { livestream, movie }

class ChannelEntity extends Equatable {
  final String id;
  final String name;
  final String url;
  final String logoUrl;
  final String group;
  final String language;
  final String country;
  final MediaType mediaType;
  final ChannelHttpHeaders httpHeaders;

  final bool isGeoBlocked;

  const ChannelEntity({
    required this.id,
    required this.name,
    required this.url,
    this.logoUrl = '',
    this.group = 'Autres',
    this.language = '',
    this.country = '',
    this.mediaType = MediaType.livestream,
    this.httpHeaders = const ChannelHttpHeaders(),
    this.isGeoBlocked = false,
  });

  bool get isLivestream => mediaType == MediaType.livestream;

  /// Clean name without geo-blocked markers
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
    String? logoUrl,
    String? group,
    String? language,
    String? country,
    MediaType? mediaType,
    ChannelHttpHeaders? httpHeaders,
    bool? isGeoBlocked,
  }) {
    return ChannelEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      logoUrl: logoUrl ?? this.logoUrl,
      group: group ?? this.group,
      language: language ?? this.language,
      country: country ?? this.country,
      mediaType: mediaType ?? this.mediaType,
      httpHeaders: httpHeaders ?? this.httpHeaders,
      isGeoBlocked: isGeoBlocked ?? this.isGeoBlocked,
    );
  }

  @override
  List<Object?> get props =>
      [id, name, url, logoUrl, group, language, country, mediaType];
}
