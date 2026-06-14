import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:iptv/config/theme/color/app_color.dart';
import 'package:iptv/config/theme/typography/app_typography.dart';
import 'package:iptv/config/routes/route_utils.dart';
import 'package:iptv/common/widgets/search_bar_widget.dart';
import 'package:iptv/common/widgets/loading_shimmer.dart';
import 'package:iptv/features/home/presentation/widgets/category_bar.dart';
import 'package:iptv/features/home/presentation/widgets/channel_grid.dart';
import 'package:iptv/features/home/provider/home_provider.dart';
import 'package:iptv/features/home/domain/entities/channel_entity.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeProvider>().loadChannels();
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
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: AppColor.primaryGradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.live_tv_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('IPTV Player', style: AppTypography.heading3),
                        Consumer<HomeProvider>(
                          builder: (context, provider, _) {
                            return Text(
                              '${provider.allChannels.length} chaînes disponibles',
                              style: AppTypography.caption,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Search
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SearchBarWidget(
                onChanged: (query) {
                  context.read<HomeProvider>().search(query);
                },
              ),
            ),

            const SizedBox(height: 16),

            // Categories
            const CategoryBar(),

            const SizedBox(height: 8),

            // Content
            Expanded(
              child: Consumer<HomeProvider>(
                builder: (context, provider, _) {
                  if (provider.isLoading) {
                    return const LoadingShimmer();
                  }
                  // Show recent/frequent sections only when no search and "Tout" selected
                  if (provider.searchQuery.isEmpty &&
                      provider.selectedGroup == 'Tout') {
                    return _buildHomeContent(provider);
                  }
                  return const ChannelGrid();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeContent(HomeProvider provider) {
    return CustomScrollView(
      slivers: [
        // Recent channels
        if (provider.recentChannels.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _buildSectionHeader('Récemment regardées'),
          ),
          SliverToBoxAdapter(
            child: _buildHorizontalChannelList(provider.recentChannels),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],

        // // Frequent channels
        // if (provider.frequentChannels.isNotEmpty) ...[
        //   SliverToBoxAdapter(
        //     child: _buildSectionHeader('Les plus regardées'),
        //   ),
        //   SliverToBoxAdapter(
        //     child: _buildHorizontalChannelList(provider.frequentChannels),
        //   ),
        //   const SliverToBoxAdapter(child: SizedBox(height: 16)),
        // ],

        // All channels header
        SliverToBoxAdapter(
          child: _buildSectionHeader('Toutes les chaînes'),
        ),

        // All channels grid
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.85,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final channel = provider.filteredChannels[index];
                return _buildGridCard(provider, channel, index);
              },
              childCount: provider.filteredChannels.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(title, style: AppTypography.heading3),
    );
  }

  Widget _buildHorizontalChannelList(List<ChannelEntity> channels) {
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: channels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final channel = channels[index];
          return GestureDetector(
            onTap: () => context.push(AppPage.player.path, extra: channel),
            child: Container(
              width: 90,
              decoration: BoxDecoration(
                color: AppColor.cardColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColor.cardHover.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: channel.logoUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: channel.logoUrl,
                            fit: BoxFit.contain,
                            placeholder: (_, _) => const Icon(
                              Icons.tv,
                              color: AppColor.textMuted,
                              size: 24,
                            ),
                            errorWidget: (_, _, _) => const Icon(
                              Icons.tv,
                              color: AppColor.textMuted,
                              size: 24,
                            ),
                          )
                        : const Icon(
                            Icons.tv,
                            color: AppColor.textMuted,
                            size: 24,
                          ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      channel.name,
                      style: AppTypography.caption.copyWith(
                        color: AppColor.textPrimary,
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGridCard(
      HomeProvider provider, ChannelEntity channel, int index) {
    return GestureDetector(
      onTap: () => context.push(AppPage.player.path, extra: channel),
      onLongPress: () => _showChannelOptions(channel),
      child: Container(
        decoration: BoxDecoration(
          color: provider.isHidden(channel.id)
              ? AppColor.cardColor.withValues(alpha: 0.4)
              : AppColor.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: provider.isHidden(channel.id)
                ? AppColor.accentRed.withValues(alpha: 0.3)
                : AppColor.cardHover.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: channel.logoUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: channel.logoUrl,
                        fit: BoxFit.contain,
                        placeholder: (_, _) => _buildPlaceholder(),
                        errorWidget: (_, _, _) => _buildPlaceholder(),
                      )
                    : _buildPlaceholder(),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      channel.cleanName,
                      style: AppTypography.body2.copyWith(
                        color: AppColor.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (channel.isGeoBlocked)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.public_off,
                              size: 14,
                              color: AppColor.accentOrange,
                            ),
                          ),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColor.primaryColor
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              provider.categoryOf(channel),
                              style: AppTypography.caption.copyWith(
                                color: AppColor.primaryLight,
                                fontSize: 10,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () =>
                              provider.toggleFavorite(channel.id),
                          child: Icon(
                            provider.isFavorite(channel.id)
                                ? Icons.favorite
                                : Icons.favorite_outline,
                            size: 18,
                            color: provider.isFavorite(channel.id)
                                ? AppColor.accentRed
                                : AppColor.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        color: AppColor.surfaceColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Icon(Icons.tv, size: 32, color: AppColor.textMuted),
      ),
    );
  }

  void _showChannelOptions(ChannelEntity channel) {
    final provider = context.read<HomeProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColor.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColor.textMuted,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(channel.name, style: AppTypography.heading3),
                const SizedBox(height: 16),
                ListTile(
                  leading: Icon(
                    provider.isFavorite(channel.id)
                        ? Icons.favorite
                        : Icons.favorite_outline,
                    color: AppColor.accentRed,
                  ),
                  title: Text(
                    provider.isFavorite(channel.id)
                        ? 'Retirer des favoris'
                        : 'Ajouter aux favoris',
                    style: AppTypography.body1,
                  ),
                  onTap: () {
                    provider.toggleFavorite(channel.id);
                    Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  leading: Icon(
                    provider.isHidden(channel.id)
                        ? Icons.visibility
                        : Icons.visibility_off,
                    color: AppColor.accentOrange,
                  ),
                  title: Text(
                    provider.isHidden(channel.id)
                        ? 'Afficher la chaîne'
                        : 'Masquer la chaîne',
                    style: AppTypography.body1,
                  ),
                  onTap: () {
                    if (provider.isHidden(channel.id)) {
                      provider.unhideChannel(channel.id);
                    } else {
                      provider.hideChannel(channel.id);
                    }
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
