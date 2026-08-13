import 'package:equatable/equatable.dart';

class AnimeEntity extends Equatable {
  final String slug;
  final String title;
  final String imageUrl;
  final String? season;
  final String? lang;

  const AnimeEntity({
    required this.slug,
    required this.title,
    this.imageUrl = '',
    this.season,
    this.lang,
  });

  @override
  List<Object?> get props => [slug, season, lang];
}

class AnimeEpisode extends Equatable {
  final int number;
  final String embedUrl;
  final String? directHlsUrl;
  final String provider;

  const AnimeEpisode({
    required this.number,
    required this.embedUrl,
    this.directHlsUrl,
    this.provider = '',
  });

  bool get hasDirectHls => directHlsUrl != null && directHlsUrl!.isNotEmpty;

  @override
  List<Object?> get props => [number, embedUrl];
}
