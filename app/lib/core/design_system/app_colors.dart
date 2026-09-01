import 'package:flutter/material.dart';

/// "Cast Iron & Chalk Dust" — FORMA's dark, utilitarian design system.
/// Ported from the Figma style-guide frame; there is no token export, so
/// values are sampled from the screenshots as closely as legibility allows.
class AppColors {
  AppColors._();

  // Surfaces — near-black, layered by elevation.
  static const Color surfaceLowest = Color(0xFF0B0C10); // scaffold background
  static const Color surfaceBase = Color(0xFF15161B); // cards
  static const Color surfaceHigh = Color(0xFF1D1E25); // sheets, elevated cards
  static const Color surfaceHighest = Color(0xFF26272F); // pressed/inputs

  // Borders.
  static const Color outlineVariant = Color(0xFF2B2C34); // hairline card border
  static const Color outline = Color(0xFF3C3E4A); // stronger / focused border

  // Text.
  static const Color textPrimary = Color(0xFFF3F3F6);
  static const Color textSecondary = Color(0xFF9A9BA6);
  static const Color textMuted = Color(0xFF6B6C78);

  // Accents — IWF competition-plate colors.
  static const Color accentBlue = Color(0xFFA9B4F5); // 20kg — primary action / links
  static const Color accentBlueDark = Color(0xFF1B1F3B); // text-on-accentBlue
  static const Color accentRed = Color(0xFFE9847E); // 25kg — PR / destructive
  static const Color accentGreen = Color(0xFF8FE3A9); // 10kg — positive / recovered
  static const Color accentWhite = Color(0xFFE8E9ED); // 5kg — neutral accent
  static const Color accentAmber = Color(0xFFE3B341); // warning / moderate severity

  static const Color error = Color(0xFFE5484D);
  static const Color success = accentGreen;
  static const Color warning = accentAmber;
}
