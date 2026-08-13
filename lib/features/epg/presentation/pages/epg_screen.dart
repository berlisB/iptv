import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:iptv/config/theme/color/app_color.dart';
import 'package:iptv/config/theme/typography/app_typography.dart';
import 'package:iptv/config/routes/route_utils.dart';
import 'package:iptv/features/epg/domain/epg_programme.dart';
import 'package:iptv/features/epg/provider/epg_provider.dart';
import 'package:iptv/features/home/domain/entities/channel_entity.dart';
import 'package:iptv/features/home/provider/home_provider.dart';

/// Écran guide des programmes TV — style grille comme une box chinoise.
/// Affiche les chaînes en colonnes avec les programmes en cours/à venir.
class EpgScreen extends StatefulWidget {
  const EpgScreen({super.key});

  @override
  State<EpgScreen> createState() => _EpgScreenState();
}

class _EpgScreenState extends State<EpgScreen> {
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();
  DateTime _selectedDate = DateTime.now();
  int _selectedHour = DateTime.now().hour;

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  List<ChannelEntity> _getChannelsWithEpg(HomeProvider hp, EpgProvider epg) {
    return hp.allChannels
        .where((c) => c.tvgId.isNotEmpty && epg.hasData)
        .take(50)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.surfaceColor,
      body: SafeArea(
        child: Consumer2<HomeProvider, EpgProvider>(
          builder: (context, hp, epg, _) {
            final channels = _getChannelsWithEpg(hp, epg);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(channels.length),
                _buildDateSelector(),
                _buildTimeBar(),
                const SizedBox(height: 8),
                Expanded(
                  child: channels.isEmpty
                      ? _buildEmptyState(epg)
                      : _buildEpgGrid(channels, epg),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(int channelCount) {
    return Padding(
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
              Icons.tv,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Guide TV', style: AppTypography.heading3),
                Text(
                  '$channelCount chaîne${channelCount > 1 ? 's' : ''} avec programme',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    final now = DateTime.now();
    final dates = List.generate(7, (i) => now.add(Duration(days: i)));

    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: dates.length,
        itemBuilder: (context, index) {
          final date = dates[index];
          final isSelected = _isSameDay(date, _selectedDate);
          final dayName = _dayName(date);
          final dayNum = date.day;

          return GestureDetector(
            onTap: () => setState(() => _selectedDate = date),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 56,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColor.primaryColor
                    : AppColor.cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? AppColor.primaryColor
                      : AppColor.cardHover.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    dayName,
                    style: AppTypography.caption.copyWith(
                      color: isSelected ? Colors.white : AppColor.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$dayNum',
                    style: AppTypography.heading3.copyWith(
                      color: isSelected ? Colors.white : AppColor.textPrimary,
                      fontSize: 18,
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

  Widget _buildTimeBar() {
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 24,
        itemBuilder: (context, index) {
          final isSelected = index == _selectedHour;
          return GestureDetector(
            onTap: () => setState(() => _selectedHour = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 56,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColor.primaryColor.withValues(alpha: 0.2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '${index.toString().padLeft(2, '0')}:00',
                  style: AppTypography.caption.copyWith(
                    color: isSelected
                        ? AppColor.primaryColor
                        : AppColor.textMuted,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w400,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(EpgProvider epg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tv_outlined,
              size: 80,
              color: AppColor.textMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 20),
            Text(
              'Guide TV non disponible',
              style: AppTypography.heading3
                  .copyWith(color: AppColor.textMuted),
            ),
            const SizedBox(height: 12),
            Text(
              epg.isLoading
                  ? 'Chargement du guide des programmes...'
                  : 'Aucun programme TV trouvé.\nLe guide sera disponible après chargement.',
              style: AppTypography.body2,
              textAlign: TextAlign.center,
            ),
            if (epg.isLoading) ...[
              const SizedBox(height: 20),
              const CircularProgressIndicator(
                color: AppColor.primaryColor,
                strokeWidth: 2,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEpgGrid(List<ChannelEntity> channels, EpgProvider epg) {
    return SingleChildScrollView(
      controller: _verticalController,
      child: Column(
        children: [
          for (final channel in channels)
            _buildChannelRow(channel, epg),
        ],
      ),
    );
  }

  Widget _buildChannelRow(ChannelEntity channel, EpgProvider epg) {
    final nn = epg.nowNext(channel.tvgId);
    final now = DateTime.now().toUtc();
    final hourStart = DateTime.utc(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedHour,
    );

    return GestureDetector(
      onTap: () => context.push(AppPage.player.path, extra: channel),
      child: Container(
        height: 72,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: AppColor.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColor.cardHover.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            // Channel logo + name
            _buildChannelInfo(channel),
            // Divider
            Container(
              width: 1,
              color: AppColor.cardHover.withValues(alpha: 0.3),
            ),
            // Programs
            Expanded(
              child: _buildPrograms(channel, nn, now, hourStart),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelInfo(ChannelEntity channel) {
    return SizedBox(
      width: 80,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (channel.logoUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Image.network(
                  channel.logoUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => _logoPlaceholder(),
                ),
              ),
            )
          else
            _logoPlaceholder(),
          const SizedBox(height: 4),
          Text(
            channel.cleanName,
            style: AppTypography.caption.copyWith(
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPrograms(
    ChannelEntity channel,
    EpgNowNext nn,
    DateTime now,
    DateTime hourStart,
  ) {
    if (nn.isEmpty) {
      return Center(
        child: Text(
          'Pas de programme',
          style: AppTypography.caption.copyWith(
            color: AppColor.textMuted,
            fontSize: 11,
          ),
        ),
      );
    }

    return Row(
      children: [
        // Current program
        if (nn.now != null)
          Expanded(
            flex: 3,
            child: _buildProgramBlock(
              nn.now!,
              isCurrent: true,
              now: now,
            ),
          ),
        // Next program
        if (nn.next != null)
          Expanded(
            flex: 2,
            child: _buildProgramBlock(
              nn.next!,
              isCurrent: false,
              now: now,
            ),
          ),
        // Remaining space
        if (nn.now == null && nn.next == null)
          Expanded(
            child: Center(
              child: Text(
                'Pas de programme',
                style: AppTypography.caption.copyWith(
                  color: AppColor.textMuted,
                  fontSize: 11,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildProgramBlock(
    EpgProgramme programme, {
    required bool isCurrent,
    required DateTime now,
  }) {
    final progress = isCurrent ? programme.progressAt(now) : 0.0;
    final startLocal = programme.start.toLocal();
    final timeStr =
        '${startLocal.hour.toString().padLeft(2, '0')}:${startLocal.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isCurrent
            ? AppColor.primaryColor.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isCurrent
            ? Border.all(
                color: AppColor.primaryColor.withValues(alpha: 0.3),
              )
            : null,
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    if (isCurrent) ...[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColor.liveColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      timeStr,
                      style: AppTypography.caption.copyWith(
                        color: isCurrent
                            ? AppColor.primaryColor
                            : AppColor.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  programme.title,
                  style: AppTypography.body2.copyWith(
                    color: isCurrent
                        ? AppColor.textPrimary
                        : AppColor.textSecondary,
                    fontWeight:
                        isCurrent ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Progress bar
          if (isCurrent)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: AppColor.cardColor,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColor.primaryColor,
                  ),
                  minHeight: 3,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _logoPlaceholder() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColor.surfaceColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: Icon(Icons.tv, size: 20, color: AppColor.textMuted),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _dayName(DateTime date) {
    const days = ['Dim', 'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam'];
    return days[date.weekday % 7];
  }
}
