import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iptv/config/routes/route_utils.dart';
import 'package:iptv/features/splash_screen/presentation/splash_screen.dart';
import 'package:iptv/features/home/presentation/pages/home_screen.dart';
import 'package:iptv/features/player/presentation/pages/player_screen.dart';
import 'package:iptv/features/favorites/presentation/pages/favorites_screen.dart';
import 'package:iptv/features/settings/presentation/pages/settings_screen.dart';
import 'package:iptv/features/epg/presentation/pages/epg_screen.dart';
import 'package:iptv/features/vod/presentation/pages/vod_screen.dart';
import 'package:iptv/features/home/domain/entities/channel_entity.dart';
import 'package:iptv/features/bottom_navigation_bar/presentation/navigator_bar.dart';

class AppRouter {
  AppRouter._();

  static final _rootNavigatorKey = GlobalKey<NavigatorState>();
  static final _shellNavigatorKey = GlobalKey<NavigatorState>();

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppPage.splash.path,
    routes: [
      GoRoute(
        path: AppPage.splash.path,
        name: AppPage.splash.name,
        builder: (context, state) => const SplashScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return NavigatorBar(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            navigatorKey: _shellNavigatorKey,
            routes: [
              GoRoute(
                path: AppPage.home.path,
                name: AppPage.home.name,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppPage.vod.path,
                name: AppPage.vod.name,
                builder: (context, state) => const VodScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppPage.epg.path,
                name: AppPage.epg.name,
                builder: (context, state) => const EpgScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppPage.favorites.path,
                name: AppPage.favorites.name,
                builder: (context, state) => const FavoritesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppPage.settings.path,
                name: AppPage.settings.name,
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppPage.player.path,
        name: AppPage.player.name,
        parentNavigatorKey: _rootNavigatorKey,
        redirect: (context, state) =>
            state.extra is ChannelEntity ? null : AppPage.home.path,
        builder: (context, state) {
          final channel = state.extra as ChannelEntity;
          return PlayerScreen(channel: channel);
        },
      ),
    ],
  );
}
