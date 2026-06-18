import 'package:get_it/get_it.dart';
import 'package:iptv/features/home/provider/home_provider.dart';
import 'package:iptv/features/favorites/provider/favorites_provider.dart';
import 'package:iptv/features/player/provider/mini_player_provider.dart';

final sl = GetIt.instance;

Future<void> initDependencies() async {
  // Providers
  sl.registerFactory<HomeProvider>(() => HomeProvider());
  sl.registerFactory<FavoritesProvider>(() => FavoritesProvider());
  sl.registerFactory<MiniPlayerProvider>(() => MiniPlayerProvider());
}
