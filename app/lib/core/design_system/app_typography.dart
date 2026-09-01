import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Type scale for "Cast Iron & Chalk Dust":
/// - Display/headers: Archivo Narrow (bold, condensed — written in caps in copy)
/// - Body: IBM Plex Sans
/// - Numeric/data (weights, percentages, timers): IBM Plex Mono
/// - Wordmark only ("FORMA" logo): a serif display face, distinct from the rest
class AppTypography {
  AppTypography._();

  static TextStyle display({double size = 32, FontWeight weight = FontWeight.w700, Color? color}) =>
      GoogleFonts.archivoNarrow(fontSize: size, fontWeight: weight, color: color ?? AppColors.textPrimary, height: 1.1);

  static TextStyle body({double size = 15, FontWeight weight = FontWeight.w400, Color? color}) =>
      GoogleFonts.ibmPlexSans(fontSize: size, fontWeight: weight, color: color ?? AppColors.textPrimary, height: 1.4);

  static TextStyle mono({double size = 15, FontWeight weight = FontWeight.w500, Color? color}) =>
      GoogleFonts.ibmPlexMono(fontSize: size, fontWeight: weight, color: color ?? AppColors.textPrimary);

  static TextStyle wordmark({double size = 28, Color? color}) =>
      GoogleFonts.playfairDisplay(fontSize: size, fontWeight: FontWeight.w800, color: color ?? AppColors.textPrimary);

  static TextTheme get textTheme => TextTheme(
    displayLarge: display(size: 40),
    displayMedium: display(size: 32),
    displaySmall: display(size: 26),
    headlineLarge: display(size: 24),
    headlineMedium: display(size: 20),
    headlineSmall: display(size: 18),
    titleLarge: body(size: 18, weight: FontWeight.w600),
    titleMedium: body(size: 16, weight: FontWeight.w600),
    titleSmall: body(size: 14, weight: FontWeight.w600),
    bodyLarge: body(size: 16),
    bodyMedium: body(size: 14),
    bodySmall: body(size: 12, color: AppColors.textSecondary),
    labelLarge: body(size: 14, weight: FontWeight.w600),
    labelMedium: body(size: 12, weight: FontWeight.w600, color: AppColors.textSecondary),
    labelSmall: body(size: 11, weight: FontWeight.w600, color: AppColors.textMuted),
  );
}
