import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iptv/features/home/provider/home_provider.dart';
import 'package:iptv/features/favorites/provider/favorites_provider.dart';
import 'package:iptv/features/player/provider/mini_player_provider.dart';
import 'package:iptv/features/epg/provider/epg_provider.dart';
import 'package:iptv/features/vod/provider/vod_provider.dart';

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
        ChangeNotifierProvider(create: (_) => EpgProvider()),
        ChangeNotifierProvider(create: (_) => VodProvider()),
      ],
      child: _AppLifecycleBridge(child: child),
    );
  }
}

/// Relaye le cycle de vie de l'app vers le player : pause hors PiP quand
/// l'app passe en arrière-plan (et gel des timers de reconnexion), reprise
/// au retour au premier plan.
class _AppLifecycleBridge extends StatefulWidget {
  final Widget child;

  const _AppLifecycleBridge({required this.child});

  @override
  State<_AppLifecycleBridge> createState() => _AppLifecycleBridgeState();
}

class _AppLifecycleBridgeState extends State<_AppLifecycleBridge>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final mp = context.read<MiniPlayerProvider>();
    switch (state) {
      case AppLifecycleState.paused:
        mp.onAppBackground();
      case AppLifecycleState.resumed:
        mp.onAppForeground();
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
