import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF14493D);
  static const primaryContainer = Color(0xFFD7EBE3);
  static const accent = Color(0xFF1E8E5A);
  static const surface = Color(0xFFFFFFFF);
  static const scaffold = Color(0xFFF6F8F9);
  static const border = Color(0xFFDDE3E8);
  static const muted = Color(0xFF5B6B79); // 5.3:1 on white
  static const danger = Color(0xFFB3261E);
  static const warning = Color(0xFF8A5300); // 6.0:1 on white
  static const warningContainer = Color(0xFFFFF1D6);
  static const dangerContainer = Color(0xFFFDE7E5);
  static const infoContainer = Color(0xFFE6EEF7);
}

/// Spacing scale — every gap and padding in the app comes from here.
class Space {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;
}

class Breakpoints {
  /// Side-by-side panes (cart + summary, form + history) from here up.
  static const wide = 900.0;

  /// Navigation rail instead of a bottom bar from here up.
  static const rail = 640.0;
}

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  bool get isWide => screenWidth >= Breakpoints.wide;
  bool get usesRail => screenWidth >= Breakpoints.rail;
}

ThemeData buildTheme() {
  const fallback = ['NotoSansDevanagari'];
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    surface: AppColors.surface,
    error: AppColors.danger,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.scaffold,
    fontFamily: 'WorkSans',
    fontFamilyFallback: fallback,
    // Standard (full touch targets) on phone; denser lists and controls on
    // Mac/Windows, where a mouse doesn't need 44pt of slack.
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );
  TextStyle? outfit(TextStyle? s) => s?.copyWith(fontFamily: 'Outfit', fontFamilyFallback: fallback);
  final text = base.textTheme;
  return base.copyWith(
    textTheme: text.copyWith(
      headlineSmall: outfit(text.headlineSmall)?.copyWith(fontWeight: FontWeight.w700),
      titleLarge: outfit(text.titleLarge)?.copyWith(fontWeight: FontWeight.w600),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.primary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      titleTextStyle: outfit(text.titleLarge)?.copyWith(fontWeight: FontWeight.w600, color: AppColors.primary),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1, thickness: 1),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: AppColors.border),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.m),
      isDense: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 44),
        padding: const EdgeInsets.symmetric(horizontal: Space.l),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 44),
        padding: const EdgeInsets.symmetric(horizontal: Space.l),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
    ),
    chipTheme: const ChipThemeData(
      side: BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: Space.l),
      minVerticalPadding: Space.s,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primaryContainer,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primaryContainer,
    ),
  );
}
