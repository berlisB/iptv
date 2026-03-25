import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iptv/config/theme/color/app_color.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColor.backgroundColor,
        colorScheme: const ColorScheme.dark(
          primary: AppColor.primaryColor,
          secondary: AppColor.primaryLight,
          surface: AppColor.surfaceColor,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        cardTheme: const CardThemeData(
          color: AppColor.cardColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColor.surfaceColor,
          selectedItemColor: AppColor.primaryColor,
          unselectedItemColor: AppColor.textMuted,
        ),
      );
}
