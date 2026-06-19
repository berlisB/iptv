import 'package:iptv/core/storage/app_storage.dart';

/// Accès centralisé aux favoris. Aujourd'hui adossé à [AppStorage]
/// (SharedPreferences) ; demain on pourra brancher un backend sans toucher
/// l'UI — seule cette classe changera.
class FavoritesService {
  const FavoritesService();

  List<String> all() => AppStorage.getFavorites();

  bool isFavorite(String channelId) => AppStorage.isFavorite(channelId);

  Future<void> add(String channelId) => AppStorage.addFavorite(channelId);

  Future<void> remove(String channelId) => AppStorage.removeFavorite(channelId);

  /// Bascule l'état favori et renvoie le nouvel état.
  Future<bool> toggle(String channelId) async {
    if (AppStorage.isFavorite(channelId)) {
      await AppStorage.removeFavorite(channelId);
      return false;
    }
    await AppStorage.addFavorite(channelId);
    return true;
  }
}
