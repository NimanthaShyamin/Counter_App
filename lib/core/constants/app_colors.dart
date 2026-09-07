import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Minimal palette — deep dark + soft white + one accent
  static const Color background = Color(0xFF0A0A0F);
  static const Color surface = Color(0xFF12121A);
  static const Color surfaceLight = Color(0xFF1A1A24);
  
  // Accent — muted cool cyan
  static const Color accent = Color(0xFF6EC6FF);
  static const Color accentDim = Color(0xFF3A7CA5);

  // Text
  static const Color textPrimary = Color(0xFFF0F0F5);
  static const Color textSecondary = Color(0xFF787890);
  static const Color textMuted = Color(0xFF44445A);

  // Functional
  static const Color positive = Color(0xFF5AE4A7);
  static const Color warning = Color(0xFFE8A44A);
  static const Color danger = Color(0xFFE85A5A);

  // Borders
  static const Color border = Color(0xFF1E1E2A);
  static const Color borderLight = Color(0xFF2A2A3A);

  // Backward-compatible aliases (for history screen / notification code)
  static const Color neonCyan = accent;
  static const Color neonPink = Color(0xFFFF6B9D);
  static const Color neonPurple = accentDim;
  static const Color neonAmber = warning;
  static const Color neonGreen = positive;
  static const Color neonRed = danger;
  static const Color surfaceDark = surface;
  static const Color surfaceCard = surfaceLight;
  static const Color surfaceCardElevated = Color(0xFF1E1E2A);
  static const Color borderDark = border;
  static const Color cyanGlow = Color(0x336EC6FF);
  static const Color pinkGlow = Color(0x33FF6B9D);
  static const Color limeGlow = Color(0x335AE4A7);
  static const Color poppyCyan = accent;
  static const Color poppyPink = Color(0xFFFF6B9D);
  static const Color poppyLime = positive;
  static const Color poppyViolet = accentDim;
  static const Color poppyAmber = warning;
  static const Color poppyCoral = danger;
  static const Color borderNeonCyan = accent;
  static const Color borderNeonPink = Color(0xFFFF6B9D);
  static const Color borderGlass = Color(0x15FFFFFF);
  static const Color glassSurface = Color(0x10FFFFFF);
  static const Color textMutedOld = textMuted;
}
