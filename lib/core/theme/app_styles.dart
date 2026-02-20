import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Masari Design System — Spacing
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double base = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;
  static const double huge = 48;
  static const double massive = 64;

  /// Standard horizontal padding for screens
  static const double screenHorizontal = 24;
  static const double screenVertical = 16;

  static const EdgeInsets screenPadding = EdgeInsets.symmetric(
    horizontal: screenHorizontal,
    vertical: screenVertical,
  );
}

/// Masari Design System — Border Radius
class AppRadius {
  AppRadius._();

  static const double sm = 8;
  static const double base = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double pill = 9999;

  static BorderRadius get cardRadius => BorderRadius.circular(base);
  static BorderRadius get buttonRadius => BorderRadius.circular(base);
  static BorderRadius get pillRadius => BorderRadius.circular(pill);
  static BorderRadius get sheetRadius => const BorderRadius.vertical(
        top: Radius.circular(xl),
      );
}

/// Masari Design System — Typography
class AppTypography {
  AppTypography._();

  static TextStyle get _baseFont => GoogleFonts.inter();

  // ─── Display / Hero ─────────────────────────────────────
  static TextStyle get displayLarge => _baseFont.copyWith(
        fontSize: 48,
        fontWeight: FontWeight.w800,
        height: 1.1,
        letterSpacing: -1.5,
      );

  static TextStyle get displayMedium => _baseFont.copyWith(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        height: 1.15,
        letterSpacing: -0.5,
      );

  // ─── Headings ───────────────────────────────────────────
  static TextStyle get h1 => _baseFont.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.2,
        letterSpacing: -0.3,
      );

  static TextStyle get h2 => _baseFont.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.25,
      );

  static TextStyle get h3 => _baseFont.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.3,
      );

  // ─── Body ───────────────────────────────────────────────
  static TextStyle get bodyLarge => _baseFont.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w400,
        height: 1.5,
      );

  static TextStyle get bodyMedium => _baseFont.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.5,
      );

  static TextStyle get bodySmall => _baseFont.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.4,
      );

  // ─── Labels / Buttons ──────────────────────────────────
  static TextStyle get labelLarge => _baseFont.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.3,
      );

  static TextStyle get labelMedium => _baseFont.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.3,
      );

  static TextStyle get labelSmall => _baseFont.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: 0.5,
      );

  // ─── Caption ────────────────────────────────────────────
  static TextStyle get caption => _baseFont.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: AppColors.textSecondary,
      );

  static TextStyle get captionSmall => _baseFont.copyWith(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        height: 1.3,
        letterSpacing: 1.0,
      );
}
