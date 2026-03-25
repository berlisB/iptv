import 'package:flutter/material.dart';
import 'package:iptv/config/theme/color/app_color.dart';
import 'package:iptv/config/theme/typography/app_typography.dart';

class SearchBarWidget extends StatelessWidget {
  final ValueChanged<String> onChanged;
  final String hintText;

  const SearchBarWidget({
    super.key,
    required this.onChanged,
    this.hintText = 'Rechercher une chaîne...',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppColor.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColor.cardHover, width: 1),
      ),
      child: TextField(
        onChanged: onChanged,
        style: AppTypography.body2.copyWith(color: AppColor.textPrimary),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: AppTypography.body2.copyWith(color: AppColor.textMuted),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppColor.textMuted,
            size: 22,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}
