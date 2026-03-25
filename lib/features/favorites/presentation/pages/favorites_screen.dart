import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:iptv/config/theme/color/app_color.dart';
import 'package:iptv/config/theme/typography/app_typography.dart';
import 'package:iptv/config/routes/route_utils.dart';
import 'package:iptv/features/favorites/provider/favorites_provider.dart';
import 'package:iptv/features/home/provider/home_provider.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final homeProvider = context.read<HomeProvider>();
      context.read<FavoritesProvider>().loadFavorites(homeProvider.allChannels);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  const Icon(
                    Icons.favorite,
                    color: AppColor.accentRed,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text('Favoris', style: AppTypography.heading2),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // List
            Expanded(
              child: Consumer<FavoritesProvider>(
                builder: (context, provider, _) {
                  if (provider.favorites.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.favorite_outline,
                            size: 80,
                            color: AppColor.textMuted,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Aucun favori',
                            style: AppTypography.heading3.copyWith(
                              color: AppColor.textMuted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Ajoutez des chaînes à vos favoris\npour les retrouver ici',
                            style: AppTypography.body2,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    itemCount: provider.favorites.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final channel = provider.favorites[index];
                      return Dismissible(
                        key: Key(channel.id),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) {
                          provider.removeFavorite(channel.id);
                          context.read<HomeProvider>().toggleFavorite(channel.id);
                        },
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: AppColor.accentRed,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.delete_outline,
                            color: Colors.white,
                          ),
                        ),
                        child: GestureDetector(
                          onTap: () {
                            context.push(
                              AppPage.player.path,
                              extra: channel,
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColor.cardColor,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppColor.cardHover.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                // Logo
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: SizedBox(
                                    width: 56,
                                    height: 56,
                                    child: channel.logoUrl.isNotEmpty
                                        ? CachedNetworkImage(
                                            imageUrl: channel.logoUrl,
                                            fit: BoxFit.contain,
                                            placeholder: (_, _) =>
                                                _buildLogoPlaceholder(),
                                            errorWidget: (_, _, _) =>
                                                _buildLogoPlaceholder(),
                                          )
                                        : _buildLogoPlaceholder(),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                // Info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        channel.name,
                                        style: AppTypography.body1.copyWith(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColor.primaryColor
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          channel.group,
                                          style:
                                              AppTypography.caption.copyWith(
                                            color: AppColor.primaryLight,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Play icon
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColor.primaryColor
                                        .withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow_rounded,
                                    color: AppColor.primaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoPlaceholder() {
    return Container(
      color: AppColor.surfaceColor,
      child: const Center(
        child: Icon(Icons.tv, size: 24, color: AppColor.textMuted),
      ),
    );
  }
}
