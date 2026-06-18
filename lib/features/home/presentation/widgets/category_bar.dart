import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iptv/config/theme/color/app_color.dart';
import 'package:iptv/config/theme/typography/app_typography.dart';
import 'package:iptv/features/home/provider/home_provider.dart';

/// Barre de catégories horizontale toujours visible : filtrage en un seul tap.
class CategoryBar extends StatelessWidget {
  const CategoryBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeProvider>(
      builder: (context, provider, _) {
        // "Tout" + catégories déjà triées par nombre de chaînes décroissant.
        final names = provider.groupNames;
        return SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: names.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              // Dernier élément : chip "⋯" ouvrant la liste complète + recherche.
              if (index == names.length) {
                return _Chip(
                  label: 'Plus',
                  icon: Icons.tune_rounded,
                  selected: false,
                  onTap: () => FilterSheetHelper.show(context, provider),
                );
              }
              final name = names[index];
              return _Chip(
                label: name,
                icon: index == 0 ? Icons.grid_view_rounded : null,
                selected: provider.selectedGroup == name,
                onTap: () => provider.selectGroup(name),
              );
            },
          ),
        );
      },
    );
  }
}

/// Pastille de catégorie cliquable (état sélectionné mis en avant).
class _Chip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColor.primaryColor : AppColor.cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColor.primaryColor : AppColor.cardHover,
          ),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 16,
                  color: selected ? Colors.white : AppColor.textSecondary),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: AppTypography.body2.copyWith(
                color: selected ? Colors.white : AppColor.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FilterSheetHelper {
  FilterSheetHelper._();

  static void show(BuildContext context, HomeProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColor.surfaceColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _FilterSheet(provider: provider),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  final HomeProvider provider;
  const _FilterSheet({required this.provider});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final groups = widget.provider.groups.where((g) {
      if (_search.isEmpty) return true;
      return g.name.toLowerCase().contains(_search.toLowerCase());
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColor.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text('Catégories', style: AppTypography.heading3),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColor.primaryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${widget.provider.groups.length}',
                      style: AppTypography.caption
                          .copyWith(color: AppColor.primaryLight),
                    ),
                  ),
                  const Spacer(),
                  if (widget.provider.hasActiveFilters)
                    TextButton(
                      onPressed: () {
                        widget.provider.clearAllFilters();
                        setState(() {});
                      },
                      child: Text(
                        'Tout effacer',
                        style: AppTypography.body2
                            .copyWith(color: AppColor.accentRed),
                      ),
                    ),
                ],
              ),
            ),

            // Search
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: AppColor.cardColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColor.cardHover),
                ),
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  style: AppTypography.body2
                      .copyWith(color: AppColor.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Rechercher une catégorie...',
                    hintStyle:
                        AppTypography.body2.copyWith(color: AppColor.textMuted),
                    prefixIcon: const Icon(Icons.search,
                        color: AppColor.textMuted, size: 20),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ),

            // Category list
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: groups.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _buildCategoryTile(
                      name: 'Tout',
                      count: widget.provider.allChannels.length,
                      icon: Icons.grid_view_rounded,
                      isSelected: widget.provider.selectedGroup == 'Tout',
                      onTap: () {
                        widget.provider.selectGroup('Tout');
                        Navigator.pop(context);
                      },
                    );
                  }
                  final group = groups[index - 1];
                  return _buildCategoryTile(
                    name: group.name,
                    count: group.count,
                    icon: _iconForGroup(group.name),
                    isSelected: widget.provider.selectedGroup == group.name,
                    onTap: () {
                      widget.provider.selectGroup(group.name);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCategoryTile({
    required String name,
    required int count,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      tileColor:
          isSelected ? AppColor.primaryColor.withValues(alpha: 0.12) : null,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColor.primaryColor.withValues(alpha: 0.2)
              : AppColor.cardColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon,
            size: 18,
            color:
                isSelected ? AppColor.primaryColor : AppColor.textSecondary),
      ),
      title: Text(
        name,
        style: AppTypography.body2.copyWith(
          color: isSelected ? AppColor.primaryColor : AppColor.textPrimary,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColor.primaryColor.withValues(alpha: 0.15)
              : AppColor.cardColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$count',
          style: AppTypography.caption.copyWith(
            color: isSelected ? AppColor.primaryLight : AppColor.textMuted,
            fontSize: 11,
          ),
        ),
      ),
      onTap: onTap,
    );
  }

  IconData _iconForGroup(String name) {
    final n = name.toLowerCase();
    if (n.contains('actualit') || n.contains('news')) return Icons.newspaper;
    if (n.contains('sport')) return Icons.sports_soccer;
    if (n.contains('film') || n.contains('séri')) return Icons.movie;
    if (n.contains('musique') || n.contains('music')) return Icons.music_note;
    if (n.contains('enfant') || n.contains('kid')) return Icons.child_care;
    if (n.contains('divertis') || n.contains('entertain')) return Icons.theater_comedy;
    if (n.contains('document')) return Icons.description;
    if (n.contains('lifestyle')) return Icons.spa;
    if (n.contains('religio')) return Icons.church;
    if (n.contains('business')) return Icons.business;
    if (n.contains('shopping')) return Icons.shopping_bag;
    if (n.contains('auto') || n.contains('tech')) return Icons.directions_car;
    if (n.contains('politiq')) return Icons.gavel;
    if (n.contains('adulte')) return Icons.no_adult_content;
    if (n.contains('général') || n.contains('general')) return Icons.live_tv;
    if (n.contains('autres')) return Icons.more_horiz;
    return Icons.tv;
  }
}
