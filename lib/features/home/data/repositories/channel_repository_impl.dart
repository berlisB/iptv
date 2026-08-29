import 'package:iptv/core/storage/app_storage.dart';
import 'package:iptv/features/home/data/datasources/catalog_v3_source.dart';
import 'package:iptv/features/home/domain/entities/channel_entity.dart';
import 'package:iptv/features/home/domain/repositories/channel_repository.dart';

class ChannelRepositoryImpl implements ChannelRepository {
  @override
  Future<List<ChannelEntity>> getCuratedChannels() async {
    // Catalogue v3 (CI toutes les 6 h) : Worker → GitHub raw → cache → asset.
    final channels = await CatalogV3Source.load();
    // Le score persistant (decay au fil des lectures) prime sur la valeur seed.
    return channels.map((c) {
      final stored = AppStorage.getScore(c.id);
      final checkedAt = AppStorage.getCheckedAt(c.id);
      return c.copyWith(
        reliabilityScore: stored,
        lastCheckedAt: checkedAt ?? c.lastCheckedAt,
        // Si l'historique local le contredit, on dégrade le status seed.
        status: AppStorage.isDead(c.id) ? ChannelStatus.offline : c.status,
      );
    }).toList();
  }
}
