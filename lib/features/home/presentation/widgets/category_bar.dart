import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iptv/config/theme/color/app_color.dart';
import 'package:iptv/config/theme/typography/app_typography.dart';
import 'package:iptv/features/home/provider/home_provider.dart';
import 'package:iptv/utils/country_names.dart';

class CategoryBar extends StatelessWidget {
  const CategoryBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeProvider>(
      builder: (context, provider, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // Filter button
              Expanded(
                child: GestureDetector(
                  onTap: () => _showFilterSheet(context, provider),
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: provider.hasActiveFilters
                          ? AppColor.primaryColor
                          : AppColor.cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: provider.hasActiveFilters
                            ? AppColor.primaryColor
                            : AppColor.cardHover,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.tune_rounded,
                          size: 18,
                          color: provider.hasActiveFilters
                              ? Colors.white
                              : AppColor.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _buildFilterLabel(provider),
                            style: AppTypography.body2.copyWith(
                              color: provider.hasActiveFilters
                                  ? Colors.white
                                  : AppColor.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (provider.hasActiveFilters)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${provider.activeFilterCount}',
                              style: AppTypography.caption.copyWith(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          )
                        else
                          Icon(Icons.keyboard_arrow_down,
                              size: 20, color: AppColor.textMuted),
                      ],
                    ),
                  ),
                ),
              ),
              // Clear button
              if (provider.hasActiveFilters) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => provider.clearAllFilters(),
                  child: Container(
                    height: 42,
                    width: 42,
                    decoration: BoxDecoration(
                      color: AppColor.accentRed.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.close,
                        size: 18, color: AppColor.accentRed),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _buildFilterLabel(HomeProvider provider) {
    if (!provider.hasActiveFilters) {
      return 'Filtres (${provider.filteredChannels.length} chaînes)';
    }
    final parts = <String>[];
    if (provider.selectedGroup != 'Tout') {
      parts.add(provider.selectedGroup);
    }
    for (final c in provider.selectedCountries) {
      parts.add(c);
    }
    for (final l in provider.selectedLanguages) {
      parts.add(l);
    }
    return parts.join(', ');
  }

  void _showFilterSheet(BuildContext context, HomeProvider provider) {
    FilterSheetHelper.show(context, provider);
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

class _FilterSheetState extends State<_FilterSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
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
                  Text('Filtres', style: AppTypography.heading3),
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
                    hintText: 'Rechercher...',
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

            // Tabs
            TabBar(
              controller: _tabController,
              labelColor: AppColor.primaryColor,
              unselectedLabelColor: AppColor.textMuted,
              indicatorColor: AppColor.primaryColor,
              labelStyle: AppTypography.body2.copyWith(fontWeight: FontWeight.w600),
              tabs: [
                Tab(text: 'Catégorie (${widget.provider.groups.length})'),
                Tab(text: 'Pays (${widget.provider.countryCounts.length})'),
                Tab(text: 'Langue (${widget.provider.languageCounts.length})'),
              ],
            ),

            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildCategoryTab(scrollController),
                  _buildCountryTab(scrollController),
                  _buildLanguageTab(scrollController),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCategoryTab(ScrollController controller) {
    final groups = widget.provider.groups.where((g) {
      if (_search.isEmpty) return true;
      return g.name.toLowerCase().contains(_search.toLowerCase());
    }).toList();

    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: groups.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildFilterTile(
            name: 'Tout',
            count: widget.provider.allChannels.length,
            icon: Icons.grid_view_rounded,
            isSelected: widget.provider.selectedGroup == 'Tout',
            onTap: () {
              widget.provider.selectGroup('Tout');
              setState(() {});
            },
          );
        }
        final group = groups[index - 1];
        return _buildFilterTile(
          name: group.name,
          count: group.count,
          icon: _iconForGroup(group.name),
          isSelected: widget.provider.selectedGroup == group.name,
          onTap: () {
            widget.provider.selectGroup(group.name);
            setState(() {});
          },
        );
      },
    );
  }

  Widget _buildCountryTab(ScrollController controller) {
    final sorted = widget.provider.countryCounts.entries.where((e) {
      if (_search.isEmpty) return true;
      final fullName = CountryNames.getFullName(e.key).toLowerCase();
      final q = _search.toLowerCase();
      return e.key.toLowerCase().contains(q) || fullName.contains(q);
    }).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final entry = sorted[index];
        final isSelected =
            widget.provider.selectedCountries.contains(entry.key);
        return _buildFilterTile(
          name: CountryNames.getFullName(entry.key),
          count: entry.value,
          icon: Icons.public,
          isSelected: isSelected,
          isCheckbox: true,
          onTap: () {
            widget.provider.toggleCountry(entry.key);
            setState(() {});
          },
        );
      },
    );
  }

  Widget _buildLanguageTab(ScrollController controller) {
    final sorted = widget.provider.languageCounts.entries.where((e) {
      if (_search.isEmpty) return true;
      return e.key.toLowerCase().contains(_search.toLowerCase());
    }).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final entry = sorted[index];
        final isSelected =
            widget.provider.selectedLanguages.contains(entry.key);
        return _buildFilterTile(
          name: entry.key,
          count: entry.value,
          icon: Icons.translate,
          isSelected: isSelected,
          isCheckbox: true,
          onTap: () {
            widget.provider.toggleLanguage(entry.key);
            setState(() {});
          },
        );
      },
    );
  }

  Widget _buildFilterTile({
    required String name,
    required int count,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    bool isCheckbox = false,
  }) {
    return ListTile(
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      tileColor:
          isSelected ? AppColor.primaryColor.withValues(alpha: 0.12) : null,
      leading: isCheckbox
          ? Checkbox(
              value: isSelected,
              onChanged: (_) => onTap(),
              activeColor: AppColor.primaryColor,
              side: const BorderSide(color: AppColor.textMuted),
            )
          : Container(
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
                  color: isSelected
                      ? AppColor.primaryColor
                      : AppColor.textSecondary),
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
    if (n.contains('news') || n.contains('info')) return Icons.newspaper;
    if (n.contains('sport')) return Icons.sports_soccer;
    if (n.contains('movie') || n.contains('film') || n.contains('cinema')) {
      return Icons.movie;
    }
    if (n.contains('music') || n.contains('musique')) return Icons.music_note;
    if (n.contains('kid') || n.contains('enfant') || n.contains('jeunesse')) {
      return Icons.child_care;
    }
    if (n.contains('entertain')) return Icons.theater_comedy;
    if (n.contains('document')) return Icons.description;
    if (n.contains('anim')) return Icons.animation;
    if (n.contains('series') || n.contains('série')) return Icons.tv;
    if (n.contains('religio')) return Icons.church;
    if (n.contains('cook')) return Icons.restaurant;
    if (n.contains('travel')) return Icons.flight;
    if (n.contains('science')) return Icons.science;
    if (n.contains('education')) return Icons.school;
    if (n.contains('weather')) return Icons.cloud;
    if (n.contains('shop')) return Icons.shopping_bag;
    if (n.contains('lifestyle')) return Icons.spa;
    if (n.contains('general')) return Icons.live_tv;
    if (n.contains('legislat')) return Icons.gavel;
    if (n.contains('family')) return Icons.family_restroom;
    if (n.contains('comedy')) return Icons.sentiment_very_satisfied;
    if (n.contains('classic')) return Icons.auto_awesome;
    if (n.contains('outdoor')) return Icons.park;
    if (n.contains('relax')) return Icons.self_improvement;
    if (n.contains('business')) return Icons.business;
    if (n.contains('culture')) return Icons.museum;
    if (n.contains('auto')) return Icons.directions_car;
    return Icons.tv;
  }
}
