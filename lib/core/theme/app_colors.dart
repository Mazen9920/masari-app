import 'package:flutter/material.dart';

/// Revvo Design System — Color Tokens
/// Single source of truth. Never use raw hex values elsewhere.
class AppColors {
  AppColors._();

  // ─── Brand Colors ───────────────────────────────────────
  static const Color primaryNavy = Color(0xFF1B4F72);
  static const Color secondaryBlue = Color(0xFF2E86C1);
  static const Color accentOrange = Color(0xFFE67E22);
  static const Color accentOrangeDark = Color(0xFFD35400);

  // ─── Semantic Colors ────────────────────────────────────
  static const Color success = Color(0xFF27AE60);
  static const Color successLight = Color(0xFFEAFAF1);
  static const Color danger = Color(0xFFE74C3C);
  static const Color dangerLight = Color(0xFFFDEDEC);
  static const Color warning = Color(0xFFF39C12);
  static const Color warningLight = Color(0xFFFEF9E7);

  // ─── Light Theme ────────────────────────────────────────
  static const Color backgroundLight = Color(0xFFF8F9FA);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1C2833);
  static const Color textSecondary = Color(0xFF7F8C8D);
  static const Color textTertiary = Color(0xFFBDC3C7);
  static const Color borderLight = Color(0xFFE5E8EB);
  static const Color dividerLight = Color(0xFFF0F0F0);
  static const Color surfaceSubtle = Color(0xFFF8FAFC);

  // ─── Integration Colors ─────────────────────────────────
  static const Color shopifyPurple = Color(0xFF7C3AED);

  // ─── Dark Theme ─────────────────────────────────────────
  static const Color backgroundDark = Color(0xFF0D1117);
  static const Color surfaceDark = Color(0xFF161B22);
  static const Color textPrimaryDark = Color(0xFFE6EDF3);
  static const Color textSecondaryDark = Color(0xFF8B949E);
  static const Color textTertiaryDark = Color(0xFF484F58);
  static const Color borderDark = Color(0xFF30363D);
  static const Color dividerDark = Color(0xFF21262D);

  // ─── Chart Colors ────────────────────────────────────────
  static const Color chartGreen = Color(0xFF10B981);
  static const Color chartGreenLight = Color(0xFFF0FDF4);
  static const Color chartRed = Color(0xFFEF4444);
  static const Color chartRedLight = Color(0xFFFEF2F2);
  static const Color chartBlue = Color(0xFF3B82F6);
  static const Color chartBlueLight = Color(0xFFEFF6FF);
  static const Color chartOrange = Color(0xFFF59E0B);
  static const Color chartOrangeLight = Color(0xFFFFFBEB);
  static const Color chartPurple = Color(0xFF8B5CF6);
  static const Color chartPurpleLight = Color(0xFFF5F3FF);
  static const Color chartIndigo = Color(0xFF6366F1);

  // ─── Badge Colors ──────────────────────────────────────
  static const Color badgeBgPositive = Color(0xFFDCFCE7);
  static const Color badgeBgNegative = Color(0xFFFEE2E2);
  static const Color badgeTextPositive = Color(0xFF15803D);
  static const Color badgeTextNegative = Color(0xFFDC2626);

  // ─── Gradients ──────────────────────────────────────────
  static const LinearGradient splashGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [primaryNavy, secondaryBlue],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentOrange, Color(0xFFFF9F4D)],
  );

  static const LinearGradient navyGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryNavy, secondaryBlue, shopifyPurple],
  );

  // ─── Shadows ────────────────────────────────────────────
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get accentShadow => [
        BoxShadow(
          color: accentOrange.withValues(alpha: 0.3),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> get navyShadow => [
        BoxShadow(
          color: primaryNavy.withValues(alpha: 0.3),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];
}
