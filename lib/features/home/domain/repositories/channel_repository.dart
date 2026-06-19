import 'package:iptv/features/home/domain/entities/channel_entity.dart';

/// Frontière d'accès aux chaînes curées. L'UI/les providers dépendent de cette
/// abstraction, jamais d'une source concrète (asset, HTTP, backend…).
abstract class ChannelRepository {
  /// Retourne le catalogue curé ("Sélection fiable"), score persistant appliqué.
  Future<List<ChannelEntity>> getCuratedChannels();
}
