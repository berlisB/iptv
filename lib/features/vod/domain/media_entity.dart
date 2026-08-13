import 'package:equatable/equatable.dart';

enum MediaType { movie, tv }

class TvSeason extends Equatable {
  final int seasonNumber;
  final int episodeCount;
  final String name;

  const TvSeason({
    required this.seasonNumber,
    required this.episodeCount,
    this.name = '',
  });

  String get label => name.isNotEmpty ? name : 'Saison $seasonNumber';

  @override
  List<Object?> get props => [seasonNumber];
}

class TvEpisode extends Equatable {
  final int seasonNumber;
  final int episodeNumber;
  final String name;
  final String overview;
  final String airDate;

  const TvEpisode({
    required this.seasonNumber,
    required this.episodeNumber,
    this.name = '',
    this.overview = '',
    this.airDate = '',
  });

  String get title =>
      name.isNotEmpty ? 'E$episodeNumber - $name' : 'Épisode $episodeNumber';

  String get year => airDate.length >= 4 ? airDate.substring(0, 4) : '';

  @override
  List<Object?> get props => [seasonNumber, episodeNumber];
}

class MediaEntity extends Equatable {
  final int tmdbId;
  final String title;
  final String overview;
  final String posterPath;
  final String backdropPath;
  final double voteAverage;
  final String releaseDate;
  final MediaType mediaType;
  final List<String> genres;
  final int? seasonCount;
  final int? episodeCount;

  const MediaEntity({
    required this.tmdbId,
    required this.title,
    this.overview = '',
    this.posterPath = '',
    this.backdropPath = '',
    this.voteAverage = 0,
    this.releaseDate = '',
    required this.mediaType,
    this.genres = const [],
    this.seasonCount,
    this.episodeCount,
  });

  String get fullPosterUrl =>
      posterPath.isNotEmpty ? 'https://image.tmdb.org/t/p/w500$posterPath' : '';

  String get fullBackdropUrl =>
      backdropPath.isNotEmpty
          ? 'https://image.tmdb.org/t/p/w780$backdropPath'
          : '';

  String get year => releaseDate.length >= 4 ? releaseDate.substring(0, 4) : '';

  String get rating => voteAverage.toStringAsFixed(1);

  bool get isMovie => mediaType == MediaType.movie;
  bool get isTv => mediaType == MediaType.tv;

  @override
  List<Object?> get props => [tmdbId, title, mediaType];
}
