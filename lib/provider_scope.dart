import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iptv/features/home/provider/home_provider.dart';
import 'package:iptv/features/favorites/provider/favorites_provider.dart';
import 'package:iptv/features/player/provider/mini_player_provider.dart';

class ProviderScope extends StatelessWidget {
  final Widget child;

  const ProviderScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => HomeProvider()),
        ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ChangeNotifierProvider(create: (_) => MiniPlayerProvider()),
      ],
      child: child,
    );
  }
}
