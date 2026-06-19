import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iptv/config/theme/color/app_color.dart';
import 'package:iptv/config/theme/typography/app_typography.dart';
import 'package:iptv/core/storage/app_storage.dart';
import 'package:iptv/features/home/provider/home_provider.dart';
import 'package:iptv/features/home/presentation/widgets/category_bar.dart';
import 'package:iptv/features/settings/presentation/widgets/xtream_settings.dart';


class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final hp = context.watch<HomeProvider>();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.settings, color: AppColor.textPrimary, size: 28),
                const SizedBox(width: 12),
                Text('Paramètres', style: AppTypography.heading2),
              ],
            ),
            const SizedBox(height: 24),

            // --- Filtrage ---
            _buildSectionTitle('Filtrage des chaînes'),
            const SizedBox(height: 8),
            _buildToggleTile(
              icon: Icons.visibility_off_outlined,
              title: 'Chaînes masquées',
              subtitle: '${hp.hiddenCount} chaînes masquées',
              value: hp.showHidden,
              onChanged: (_) => hp.toggleShowHidden(),
            ),
            _buildToggleTile(
              icon: Icons.public_off,
              title: 'Chaînes géo-bloquées',
              subtitle: '${hp.geoBlockedCount} chaînes détectées',
              value: hp.showGeoBlocked,
              onChanged: (_) => hp.toggleShowGeoBlocked(),
            ),
            _buildToggleTile(
              icon: Icons.no_adult_content,
              title: 'Contenu adulte (XXX)',
              subtitle: 'Masqué par défaut pour votre sécurité',
              value: hp.showAdult,
              activeColor: AppColor.accentRed,
              onChanged: (_) => hp.toggleShowAdult(),
            ),
            _buildToggleTile(
              icon: Icons.help_outline,
              title: 'Chaînes non classées',
              subtitle: 'Masquer les chaînes sans catégorie',
              value: !hp.showUndefined,
              onChanged: (_) => hp.toggleShowUndefined(),
            ),

            const SizedBox(height: 24),

            // --- Sources ---
            _buildSectionTitle('Sources'),
            const SizedBox(height: 8),
            _buildToggleTile(
              icon: Icons.sports_esports_outlined,
              title: 'Daddylive (étude éducative)',
              subtitle: hp.daddyliveEnabled
                  ? 'Active · ${hp.rawChannels.where((c) => c.id.startsWith('daddylive_')).length} chaînes'
                  : 'Désactivée · Sport & divertissement',
              value: hp.daddyliveEnabled,
              activeColor: AppColor.accentRed,
              onChanged: (v) async {
                await AppStorage.setDaddyliveEnabled(v);
                hp.loadChannels();
              },
            ),

            const SizedBox(height: 24),

            // --- Abonnement ---
            _buildSectionTitle('Abonnement (IPTV premium)'),
            const SizedBox(height: 8),
            const XtreamSettingsTile(),

            const SizedBox(height: 24),

            // --- Lecture ---
            _buildSectionTitle('Lecture & Buffer'),
            const SizedBox(height: 8),
            _buildBufferSelector(),

            const SizedBox(height: 24),

            // --- Filtres actifs ---
            _buildSectionTitle('Filtres de recherche'),
            const SizedBox(height: 8),

            // Open filter sheet
            _buildActionTile(
              icon: Icons.tune_rounded,
              title: 'Configurer les filtres',
              subtitle: hp.hasActiveFilters
                  ? '${hp.activeFilterCount} filtre(s) actif(s)'
                  : 'Choisir une catégorie',
              color: AppColor.primaryColor,
              onTap: () => FilterSheetHelper.show(context, hp),
            ),

            // Active filters summary
            if (hp.hasActiveFilters) ...[
              const SizedBox(height: 8),
              _buildActiveFilters(hp),
            ],

            const SizedBox(height: 24),

            // --- Gestion ---
            _buildSectionTitle('Gestion'),
            const SizedBox(height: 8),
            _buildActionTile(
              icon: Icons.restore,
              title: 'Restaurer les chaînes masquées',
              subtitle: '${hp.hiddenCount} chaînes',
              color: AppColor.accentOrange,
              onTap: hp.hiddenCount > 0
                  ? () {
                      hp.clearHiddenChannels();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Toutes les chaînes restaurées'),
                          backgroundColor: AppColor.surfaceColor,
                          duration: const Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  : null,
            ),
            _buildActionTile(
              icon: Icons.delete_sweep,
              title: 'Vider la blocklist locale',
              subtitle: '${AppStorage.getLocalBlocklist().length} URLs',
              color: AppColor.accentRed,
              onTap: AppStorage.getLocalBlocklist().isNotEmpty
                  ? () async {
                      await AppStorage.clearLocalBlocklist();
                      setState(() {});
                    }
                  : null,
            ),
            _buildActionTile(
              icon: Icons.bar_chart_rounded,
              title: 'Statistiques',
              subtitle: '${hp.allChannels.length} chaînes, ${hp.groups.length} catégories',
              color: AppColor.accentBlue,
              onTap: () => _showStatsSheet(hp),
            ),

            const SizedBox(height: 24),

            // --- About ---
            _buildSectionTitle('À propos'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColor.cardColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: AppColor.primaryGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.live_tv, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('IPTV Player v1.0.0',
                            style: AppTypography.body1
                                .copyWith(fontWeight: FontWeight.w600)),
                        Text('Lecteur IPTV avancé',
                            style: AppTypography.caption),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveFilters(HomeProvider hp) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (hp.selectedGroup != 'Tout')
          _buildChip(hp.selectedGroup, () => hp.selectGroup('Tout')),
        // Clear all
        GestureDetector(
          onTap: () => hp.clearAllFilters(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColor.accentRed.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('Tout effacer',
                style: AppTypography.caption
                    .copyWith(color: AppColor.accentRed, fontSize: 11)),
          ),
        ),
      ],
    );
  }

  Widget _buildChip(String label, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColor.primaryColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: AppTypography.caption
                  .copyWith(color: AppColor.primaryLight, fontSize: 11)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, size: 14, color: AppColor.primaryLight),
          ),
        ],
      ),
    );
  }

  void _showStatsSheet(HomeProvider hp) {
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
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColor.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text('Statistiques', style: AppTypography.heading3),
            const SizedBox(height: 16),
            _statRow('Total chaînes', '${hp.allChannels.length}'),
            _statRow('Affichées', '${hp.filteredChannels.length}'),
            _statRow('Catégories', '${hp.groups.length}'),
            _statRow('Géo-bloquées', '${hp.geoBlockedCount}'),
            _statRow('Masquées', '${hp.hiddenCount}'),
            _statRow('Blocklist locale', '${AppStorage.getLocalBlocklist().length}'),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.body2),
          Text(value, style: AppTypography.body2.copyWith(
            color: AppColor.primaryLight, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildBufferSelector() {
    final level = AppStorage.getBufferLevel();
    const levels = [
      ('Faible', 'Latence minimale, moins stable', Icons.speed),
      ('Normal', '60s de cache, équilibré', Icons.tune),
      ('Élevé', '3 min de pré-chargement, comme YouTube', Icons.download_for_offline),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColor.cardColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cached_rounded, color: AppColor.primaryColor, size: 20),
              const SizedBox(width: 8),
              Text('Niveau de buffer', style: AppTypography.body1),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Un buffer élevé pré-charge le flux pour éviter les coupures',
            style: AppTypography.caption,
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(3, (i) {
              final selected = i == level;
              final (name, subtitle, icon) = levels[i];
              return Expanded(
                child: GestureDetector(
                  onTap: () async {
                    await AppStorage.setBufferLevel(i);
                    setState(() {});
                  },
                  child: Container(
                    margin: EdgeInsets.only(left: i > 0 ? 8 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColor.primaryColor.withValues(alpha: 0.2)
                          : AppColor.surfaceColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected ? AppColor.primaryColor : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(icon,
                            color: selected ? AppColor.primaryColor : AppColor.textMuted,
                            size: 22),
                        const SizedBox(height: 4),
                        Text(name,
                            style: AppTypography.caption.copyWith(
                              color: selected ? AppColor.primaryLight : AppColor.textSecondary,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                              fontSize: 12,
                            )),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            textAlign: TextAlign.center,
                            style: AppTypography.caption.copyWith(fontSize: 9)),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: AppTypography.caption.copyWith(
        color: AppColor.primaryLight,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildToggleTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color? activeColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColor.cardColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: SwitchListTile(
        secondary: Icon(icon,
            color: value ? (activeColor ?? AppColor.primaryColor) : AppColor.textMuted),
        title: Text(title, style: AppTypography.body1),
        subtitle: Text(subtitle, style: AppTypography.caption),
        value: value,
        activeTrackColor:
            (activeColor ?? AppColor.primaryColor).withValues(alpha: 0.5),
        thumbColor: WidgetStatePropertyAll(
            value ? (activeColor ?? AppColor.primaryColor) : AppColor.textMuted),
        onChanged: onChanged,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColor.cardColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        leading: Icon(icon, color: onTap != null ? color : AppColor.textMuted),
        title: Text(title,
            style: AppTypography.body1.copyWith(
                color: onTap != null ? AppColor.textPrimary : AppColor.textMuted)),
        subtitle: Text(subtitle, style: AppTypography.caption),
        trailing: const Icon(Icons.chevron_right, color: AppColor.textMuted),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
