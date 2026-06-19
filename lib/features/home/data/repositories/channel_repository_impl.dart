import 'package:iptv/core/storage/app_storage.dart';
import 'package:iptv/features/home/data/datasources/channel_catalog_source.dart';
import 'package:iptv/features/home/domain/entities/channel_entity.dart';
import 'package:iptv/features/home/domain/repositories/channel_repository.dart';

class ChannelRepositoryImpl implements ChannelRepository {
  ChannelRepositoryImpl({ChannelCatalogSource? catalogSource})
      : _catalog = catalogSource ?? ChannelCatalogSource();

  final ChannelCatalogSource _catalog;

  @override
  Future<List<ChannelEntity>> getCuratedChannels() async {
    final channels = await _catalog.load();
    // Le score persistant (decay au fil des lectures) prime sur la valeur seed.
    return channels.map((c) {
      final stored = AppStorage.getScore(c.id);
      final checkedAt = AppStorage.getCheckedAt(c.id);
      return c.copyWith(
        reliabilityScore: stored,
        lastCheckedAt: checkedAt,
        // Si l'historique local le contredit, on dégrade le status seed.
        status: AppStorage.isDead(c.id) ? ChannelStatus.offline : c.status,
      );
    }).toList();
  }
}
