import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:iptv/common/widgets/channel_card.dart';
import 'package:iptv/config/routes/route_utils.dart';
import 'package:iptv/features/home/provider/home_provider.dart';
import 'package:iptv/config/theme/color/app_color.dart';
import 'package:iptv/config/theme/typography/app_typography.dart';

class ChannelGrid extends StatefulWidget {
  const ChannelGrid({super.key});

  @override
  State<ChannelGrid> createState() => _ChannelGridState();
}

class _ChannelGridState extends State<ChannelGrid> {
  bool _isRefreshing = false;

  Future<void> _onRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    
    final provider = context.read<HomeProvider>();
    await provider.loadChannels();
    
    if (mounted) {
      setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeProvider>(
      builder: (context, provider, _) {
        if (provider.filteredChannels.isEmpty && !_isRefreshing) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.search_off_rounded,
                  size: 64,
                  color: AppColor.textMuted,
                ),
                const SizedBox(height: 16),
                Text(
                  'Aucune chaîne trouvée',
                  style: AppTypography.body1.copyWith(
                    color: AppColor.textMuted,
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _onRefresh,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Rafraîchir'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColor.primaryColor,
                    side: const BorderSide(color: AppColor.primaryColor),
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _onRefresh,
          color: AppColor.primaryColor,
          backgroundColor: AppColor.surfaceColor,
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.85,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: provider.filteredChannels.length,
            itemBuilder: (context, index) {
              final channel = provider.filteredChannels[index];
              return ChannelCard(
                channel: channel,
                isFavorite: provider.isFavorite(channel.id),
                onTap: () {
                  context.push(AppPage.player.path, extra: channel);
                },
                onFavoriteTap: () => provider.toggleFavorite(channel.id),
              );
            },
          ),
        );
      },
    );
  }
}
