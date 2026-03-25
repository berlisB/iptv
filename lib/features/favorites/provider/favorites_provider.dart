import 'package:flutter/foundation.dart';
import 'package:iptv/core/storage/app_storage.dart';
import 'package:iptv/features/home/domain/entities/channel_entity.dart';

class FavoritesProvider extends ChangeNotifier {
  List<ChannelEntity> _favorites = [];

  List<ChannelEntity> get favorites => _favorites;

  void loadFavorites(List<ChannelEntity> allChannels) {
    final favoriteIds = AppStorage.getFavorites();
    _favorites =
        allChannels.where((c) => favoriteIds.contains(c.id)).toList();
    notifyListeners();
  }

  Future<void> removeFavorite(String channelId) async {
    await AppStorage.removeFavorite(channelId);
    _favorites.removeWhere((c) => c.id == channelId);
    notifyListeners();
  }

  bool isFavorite(String channelId) {
    return AppStorage.isFavorite(channelId);
  }
}
