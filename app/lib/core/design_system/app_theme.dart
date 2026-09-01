import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// FORMA ships one theme: dark. The design has no documented light variant,
/// and the style guide's own anti-patterns list (no gradients, no
/// glassmorphism, no drop shadows) is written entirely in dark-surface terms.
class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final colorScheme = const ColorScheme.dark(
      brightness: Brightness.dark,
      primary: AppColors.accentBlue,
      onPrimary: AppColors.accentBlueDark,
      secondary: AppColors.accentGreen,
      onSecondary: AppColors.accentBlueDark,
      surface: AppColors.surfaceBase,
      onSurface: AppColors.textPrimary,
      error: AppColors.error,
      onError: Colors.white,
      outline: AppColors.outline,
      outlineVariant: AppColors.outlineVariant,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.surfaceLowest,
      textTheme: AppTypography.textTheme,
      splashFactory: NoSplash.splashFactory,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.surfaceLowest,
        foregroundColor: AppColors.textPrimary,
        titleTextStyle: AppTypography.display(size: 20),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceBase,
        elevation: 0, // anti-pattern: no drop shadows on cards
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceHigh,
        hintStyle: AppTypography.body(color: AppColors.textMuted),
        labelStyle: AppTypography.body(size: 12, color: AppColors.textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: const BorderSide(color: AppColors.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: const BorderSide(color: AppColors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: const BorderSide(color: AppColors.accentBlue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accentBlue,
          foregroundColor: AppColors.accentBlueDark,
          disabledBackgroundColor: AppColors.accentBlue.withValues(alpha: 0.35),
          disabledForegroundColor: AppColors.accentBlueDark.withValues(alpha: 0.6),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
          textStyle: AppTypography.body(size: 15, weight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.outline),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
          textStyle: AppTypography.body(size: 15, weight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.accentBlue, textStyle: AppTypography.body(weight: FontWeight.w600)),
      ),
      iconTheme: const IconThemeData(color: AppColors.textSecondary),
      dividerTheme: const DividerThemeData(color: AppColors.outlineVariant, thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceHigh,
        selectedColor: AppColors.accentBlue,
        labelStyle: AppTypography.body(size: 13, weight: FontWeight.w600),
        secondaryLabelStyle: AppTypography.body(size: 13, weight: FontWeight.w600, color: AppColors.accentBlueDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.chip), side: const BorderSide(color: AppColors.outlineVariant)),
        side: const BorderSide(color: AppColors.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.accentBlue : AppColors.surfaceHighest,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.accentBlue : AppColors.textMuted,
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.accentBlue,
        inactiveTrackColor: AppColors.surfaceHighest,
        thumbColor: AppColors.accentBlue,
        overlayColor: Color(0x33A9B4F5),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accentBlue,
        linearTrackColor: AppColors.surfaceHighest,
        circularTrackColor: AppColors.surfaceHighest,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.surfaceLowest,
        selectedItemColor: AppColors.accentBlue,
        unselectedItemColor: AppColors.textMuted,
        selectedLabelStyle: AppTypography.body(size: 10, weight: FontWeight.w600),
        unselectedLabelStyle: AppTypography.body(size: 10, weight: FontWeight.w600),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceHighest,
        contentTextStyle: AppTypography.body(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.field)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      ),
    );
  }
}
