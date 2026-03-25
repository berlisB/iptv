import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iptv/config/theme/color/app_color.dart';
import 'package:iptv/features/player/presentation/widgets/mini_player.dart';

class NavigatorBar extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const NavigatorBar({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          navigationShell,
          // Floating mini player overlay
          const MiniPlayer(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColor.surfaceColor,
          border: Border(
            top: BorderSide(color: AppColor.cardColor, width: 0.5),
          ),
        ),
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          height: 65,
          selectedIndex: navigationShell.currentIndex,
          indicatorColor: AppColor.primaryColor.withValues(alpha: 0.15),
          onDestinationSelected: (index) {
            navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            );
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.live_tv_outlined, color: AppColor.textMuted),
              selectedIcon: Icon(Icons.live_tv, color: AppColor.primaryColor),
              label: 'Chaînes',
            ),
            NavigationDestination(
              icon: Icon(Icons.favorite_outline, color: AppColor.textMuted),
              selectedIcon: Icon(Icons.favorite, color: AppColor.primaryColor),
              label: 'Favoris',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined, color: AppColor.textMuted),
              selectedIcon: Icon(Icons.settings, color: AppColor.primaryColor),
              label: 'Paramètres',
            ),
          ],
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        ),
      ),
    );
  }
}
