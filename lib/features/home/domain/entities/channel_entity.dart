import 'package:equatable/equatable.dart';

class ChannelEntity extends Equatable {
  final String id;
  final String name;
  final String url;
  final String logoUrl;
  final String group;
  final String language;
  final String country;

  const ChannelEntity({
    required this.id,
    required this.name,
    required this.url,
    this.logoUrl = '',
    this.group = 'Autres',
    this.language = '',
    this.country = '',
  });

  ChannelEntity copyWith({
    String? id,
    String? name,
    String? url,
    String? logoUrl,
    String? group,
    String? language,
    String? country,
  }) {
    return ChannelEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      logoUrl: logoUrl ?? this.logoUrl,
      group: group ?? this.group,
      language: language ?? this.language,
      country: country ?? this.country,
    );
  }

  @override
  List<Object?> get props => [id, name, url, logoUrl, group, language, country];
}
