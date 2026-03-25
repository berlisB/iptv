import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iptv/common/widgets/category_chip.dart';
import 'package:iptv/features/home/provider/home_provider.dart';

class CategoryBar extends StatelessWidget {
  const CategoryBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeProvider>(
      builder: (context, provider, _) {
        return SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: provider.groupNames.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final group = provider.groupNames[index];
              return CategoryChip(
                label: group,
                isSelected: provider.selectedGroup == group,
                onTap: () => provider.selectGroup(group),
              );
            },
          ),
        );
      },
    );
  }
}
