import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Central design system for the app: a warm, energetic delivery theme with
/// matching light and dark variants. Everything visual — color, typography,
/// shape, and per-component styling — is defined here so screens can stay lean
/// and consistent.
class AppTheme {
  const AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.coral,
      brightness: brightness,
    ).copyWith(
      primary: AppColors.coral,
      onPrimary: Colors.white,
      secondary: AppColors.amber,
      onSecondary: Colors.white,
      error: AppColors.error,
      surface: isLight ? AppColors.lightSurface : AppColors.darkSurface,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
    );

    // Plus Jakarta Sans across the board, with heavier, tighter headings for
    // a punchy, modern feel.
    final jakarta = GoogleFonts.plusJakartaSansTextTheme(base.textTheme);
    final textTheme = jakarta.copyWith(
      displayLarge: _heading(jakarta.displayLarge),
      displayMedium: _heading(jakarta.displayMedium),
      displaySmall: _heading(jakarta.displaySmall),
      headlineLarge: _heading(jakarta.headlineLarge),
      headlineMedium: _heading(jakarta.headlineMedium),
      headlineSmall: _heading(jakarta.headlineSmall),
      titleLarge: _title(jakarta.titleLarge),
      titleMedium: _title(jakarta.titleMedium),
    );

    final onSurfaceVariant = scheme.onSurfaceVariant;
    final fieldFill = isLight ? AppColors.lightSurfaceVariant : AppColors.darkSurfaceVariant;

    OutlineInputBorder fieldBorder(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: width == 0 ? BorderSide.none : BorderSide(color: color, width: width),
        );

    return base.copyWith(
      scaffoldBackgroundColor: isLight ? AppColors.lightBackground : AppColors.darkBackground,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: isLight ? AppColors.lightBackground : AppColors.darkBackground,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 20),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        prefixIconColor: onSurfaceVariant,
        suffixIconColor: onSurfaceVariant,
        hintStyle: TextStyle(color: onSurfaceVariant),
        border: fieldBorder(Colors.transparent, 0),
        enabledBorder: fieldBorder(Colors.transparent, 0),
        focusedBorder: fieldBorder(scheme.primary, 2),
        errorBorder: fieldBorder(scheme.error),
        focusedErrorBorder: fieldBorder(scheme.error, 2),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surface,
        selectedColor: scheme.primaryContainer,
        checkmarkColor: scheme.onPrimaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        shape: const StadiumBorder(),
        labelStyle: textTheme.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.6),
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: onSurfaceVariant,
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle: textTheme.titleSmall,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    );
  }

  static TextStyle? _heading(TextStyle? base) =>
      base?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5);

  static TextStyle? _title(TextStyle? base) =>
      base?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2);
}
