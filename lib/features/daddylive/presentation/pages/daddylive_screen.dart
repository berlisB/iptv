import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:iptv/config/theme/color/app_color.dart';
import 'package:iptv/config/theme/typography/app_typography.dart';
import 'package:iptv/config/routes/route_utils.dart';
import 'package:iptv/features/home/provider/home_provider.dart';
import 'package:iptv/features/home/domain/entities/channel_entity.dart';

class DaddyliveScreen extends StatefulWidget {
  const DaddyliveScreen({super.key});

  @override
  State<DaddyliveScreen> createState() => _DaddyliveScreenState();
}

class _DaddyliveScreenState extends State<DaddyliveScreen> {
  List<ChannelEntity> _daddyliveChannels = [];

  @override
  Widget build(BuildContext context) {
    final hp = context.watch<HomeProvider>();

    if (hp.daddyliveEnabled && _daddyliveChannels.isEmpty) {
      _daddyliveChannels = hp.rawChannels
          .where((c) => c.id.startsWith('daddylive_'))
          .toList();
    } else if (!hp.daddyliveEnabled) {
      _daddyliveChannels = [];
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE53935), Color(0xFFFF6F00)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.sports_esports_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Daddylive', style: AppTypography.heading3),
                        Text(
                          _daddyliveChannels.isNotEmpty
                              ? '${_daddyliveChannels.length} chaînes · Sport & Divertissement'
                              : 'Source éducative',
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildContent(hp)),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(HomeProvider hp) {
    if (hp.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColor.primaryColor),
      );
    }

    if (!hp.daddyliveEnabled) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sports_esports_outlined,
                  size: 64, color: AppColor.textMuted.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text(
                'Source désactivée',
                style: AppTypography.heading3,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Activez Daddylive dans les paramètres '
                'pour accéder aux chaînes sport & divertissement.',
                style: AppTypography.body2,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.go(AppPage.settings.path),
                icon: const Icon(Icons.settings, size: 18),
                label: const Text('Paramètres'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColor.primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_daddyliveChannels.isEmpty) {
      return Center(
        child: Text('Aucune chaîne disponible',
            style: AppTypography.body2),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await hp.loadChannels();
        setState(() {
          _daddyliveChannels = hp.rawChannels
              .where((c) => c.id.startsWith('daddylive_'))
              .toList();
        });
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.85,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: _daddyliveChannels.length,
          itemBuilder: (context, index) =>
              _buildChannelCard(_daddyliveChannels[index]),
        ),
      ),
    );
  }

  Widget _buildChannelCard(ChannelEntity channel) {
    return GestureDetector(
      onTap: () => context.push(AppPage.player.path, extra: channel),
      child: Container(
        decoration: BoxDecoration(
          color: AppColor.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColor.cardHover.withValues(alpha: 0.3),
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
                        placeholder: (_, _) => _placeholder(),
                        errorWidget: (_, _, _) => _placeholder(),
                      )
                    : _placeholder(),
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColor.accentRed.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        channel.category.isNotEmpty
                            ? channel.category
                            : channel.group,
                        style: AppTypography.caption.copyWith(
                          color: AppColor.accentRed,
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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

  Widget _placeholder() {
    return Container(
      decoration: BoxDecoration(
        color: AppColor.surfaceColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Icon(Icons.sports_esports_outlined,
            size: 32, color: AppColor.textMuted),
      ),
    );
  }
}
