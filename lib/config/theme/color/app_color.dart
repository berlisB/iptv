import 'package:flutter/material.dart';

class AppColor {
  AppColor._();

  // Primary
  static const Color primaryColor = Color(0xFF6C63FF);
  static const Color primaryLight = Color(0xFF9D97FF);
  static const Color primaryDark = Color(0xFF4A42E0);

  // Background
  static const Color backgroundColor = Color(0xFF0D0D0D);
  static const Color surfaceColor = Color(0xFF1A1A2E);
  static const Color cardColor = Color(0xFF16213E);
  static const Color cardHover = Color(0xFF1E2D4F);

  // Text
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0B0B0);
  static const Color textMuted = Color(0xFF6C6C6C);

  // Accent
  static const Color accentRed = Color(0xFFE74C3C);
  static const Color accentGreen = Color(0xFF2ECC71);
  static const Color accentOrange = Color(0xFFF39C12);
  static const Color accentBlue = Color(0xFF3498DB);

  // Status
  static const Color liveColor = Color(0xFFE74C3C);
  static const Color onlineColor = Color(0xFF2ECC71);
  static const Color offlineColor = Color(0xFF6C6C6C);

  // Gradient
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryColor, Color(0xFF764BA2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkGradient = LinearGradient(
    colors: [backgroundColor, surfaceColor],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
