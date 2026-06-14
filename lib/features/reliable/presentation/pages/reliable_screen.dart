import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:iptv/config/theme/color/app_color.dart';
import 'package:iptv/config/theme/typography/app_typography.dart';
import 'package:iptv/config/routes/route_utils.dart';
import 'package:iptv/core/storage/app_storage.dart';
import 'package:iptv/features/home/domain/entities/channel_entity.dart';
import 'package:iptv/features/home/provider/home_provider.dart';

class ReliableScreen extends StatefulWidget {
  const ReliableScreen({super.key});

  @override
  State<ReliableScreen> createState() => _ReliableScreenState();
}

class _ReliableScreenState extends State<ReliableScreen> {
  String _searchQuery = '';

  List<ChannelEntity> _getReliableChannels(HomeProvider hp) {
    final confirmedIds = AppStorage.getConfirmedChannels();
    var channels = hp.allChannels
        .where((c) => confirmedIds.contains(c.id))
        .toList();

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      channels = channels
          .where((c) =>
              c.name.toLowerCase().contains(q) ||
              c.group.toLowerCase().contains(q))
          .toList();
    }

    return channels;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer<HomeProvider>(
          builder: (context, hp, _) {
            final channels = _getReliableChannels(hp);

            return Column(
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
                          color: AppColor.accentGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.verified_rounded,
                          color: AppColor.accentGreen,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Chaînes fiables',
                                style: AppTypography.heading3),
                            Text(
                              '${channels.length} chaîne${channels.length > 1 ? 's' : ''} confirmée${channels.length > 1 ? 's' : ''}',
                              style: AppTypography.caption,
                            ),
                          ],
                        ),
                      ),
                      if (channels.isNotEmpty)
                        IconButton(
                          onPressed: _showInfoSheet,
                          icon: const Icon(Icons.info_outline,
                              color: AppColor.textMuted, size: 22),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Search
                if (channels.length > 5 || _searchQuery.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      onChanged: (q) => setState(() => _searchQuery = q),
                      style: AppTypography.body2
                          .copyWith(color: AppColor.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Rechercher...',
                        hintStyle: AppTypography.body2
                            .copyWith(color: AppColor.textMuted),
                        prefixIcon: const Icon(Icons.search,
                            color: AppColor.textMuted, size: 20),
                        filled: true,
                        fillColor: AppColor.cardColor,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),

                if (channels.length > 5 || _searchQuery.isNotEmpty)
                  const SizedBox(height: 12),

                // Content
                Expanded(
                  child: channels.isEmpty
                      ? _buildEmptyState()
                      : _buildChannelList(channels, hp),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.verified_outlined,
              size: 80,
              color: AppColor.textMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 20),
            Text(
              'Aucune chaîne fiable',
              style: AppTypography.heading3
                  .copyWith(color: AppColor.textMuted),
            ),
            const SizedBox(height: 12),
            Text(
              'Les chaînes qui fonctionnent sans interruption\npendant 30 secondes sont automatiquement\najoutées ici.',
              style: AppTypography.body2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.play_arrow_rounded,
                    color: AppColor.primaryColor, size: 18),
                const SizedBox(width: 4),
                Text(
                  'Regardez des chaînes pour les tester !',
                  style: AppTypography.caption
                      .copyWith(color: AppColor.primaryLight),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelList(List<ChannelEntity> channels, HomeProvider hp) {
    // Group by category
    final Map<String, List<ChannelEntity>> grouped = {};
    for (final c in channels) {
      grouped.putIfAbsent(c.group, () => []).add(c);
    }
    final groups = grouped.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      itemCount: groups.length,
      itemBuilder: (context, groupIndex) {
        final entry = groups[groupIndex];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (groups.length > 1) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 6),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColor.primaryColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${entry.key} (${entry.value.length})',
                        style: AppTypography.caption.copyWith(
                          color: AppColor.primaryLight,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            ...entry.value.map((channel) => _buildChannelTile(channel, hp)),
          ],
        );
      },
    );
  }

  Widget _buildChannelTile(ChannelEntity channel, HomeProvider hp) {
    return Dismissible(
      key: Key('reliable_${channel.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        AppStorage.unconfirmChannel(channel.id);
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${channel.cleanName} retiré des fiables'),
            backgroundColor: AppColor.surfaceColor,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Annuler',
              textColor: AppColor.primaryColor,
              onPressed: () {
                AppStorage.confirmChannel(channel.id);
                setState(() {});
              },
            ),
          ),
        );
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColor.accentRed,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.remove_circle_outline, color: Colors.white),
      ),
      child: GestureDetector(
        onTap: () => context.push(AppPage.player.path, extra: channel),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColor.cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColor.accentGreen.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              // Logo
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 50,
                  height: 50,
                  child: channel.logoUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: channel.logoUrl,
                          fit: BoxFit.contain,
                          placeholder: (_, _) => _logoPlaceholder(),
                          errorWidget: (_, _, _) => _logoPlaceholder(),
                        )
                      : _logoPlaceholder(),
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            channel.cleanName,
                            style: AppTypography.body1
                                .copyWith(fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.verified,
                            color: AppColor.accentGreen, size: 16),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                AppColor.primaryColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            channel.group,
                            style: AppTypography.caption
                                .copyWith(color: AppColor.primaryLight),
                          ),
                        ),
                        if (channel.country.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(channel.country,
                              style: AppTypography.caption
                                  .copyWith(fontSize: 11)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Play
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColor.accentGreen.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: AppColor.accentGreen,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _logoPlaceholder() {
    return Container(
      color: AppColor.surfaceColor,
      child: const Center(
        child: Icon(Icons.tv, size: 22, color: AppColor.textMuted),
      ),
    );
  }

  void _showInfoSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColor.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
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
            const Icon(Icons.verified_rounded,
                color: AppColor.accentGreen, size: 40),
            const SizedBox(height: 12),
            Text('Comment ça marche ?', style: AppTypography.heading3),
            const SizedBox(height: 12),
            Text(
              'Quand vous regardez une chaîne et qu\'elle fonctionne '
              'sans interruption pendant 30 secondes, elle est automatiquement '
              'ajoutée à cette liste.\n\n'
              'Ces chaînes sont retirées de la liste principale pour '
              'garder uniquement les chaînes non testées.\n\n'
              'Glissez vers la gauche pour retirer une chaîne de cette liste.',
              style: AppTypography.body2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  AppStorage.clearConfirmedChannels();
                  Navigator.pop(context);
                  setState(() {});
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColor.accentRed,
                  side: const BorderSide(color: AppColor.accentRed),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Réinitialiser toutes les chaînes fiables'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
