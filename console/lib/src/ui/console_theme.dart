import 'package:flutter/material.dart';

ThemeData buildConsoleTheme() {
  final ColorScheme colorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF1A73E8),
    brightness: Brightness.light,
    surface: const Color(0xFFFFFFFF),
  );

  final TextTheme baseTextTheme = Typography.material2021().black;

  return ThemeData(
    useMaterial3: true,
    // Avoid shader-backed splash effects (InkSparkle) which require
    // compiling fragment programs and break in widget tests.
    // InkRipple is Material-compliant and does not depend on shader assets.
    splashFactory: InkRipple.splashFactory,
    colorScheme: colorScheme.copyWith(
      surfaceContainerLowest: const Color(0xFFF5F7FB),
      surfaceContainerLow: const Color(0xFFF0F4FA),
      surfaceContainer: const Color(0xFFEAF0F8),
      surfaceContainerHigh: const Color(0xFFE2E9F2),
      surfaceContainerHighest: const Color(0xFFD7E1EE),
      outlineVariant: const Color(0xFFD2D9E3),
    ),
    scaffoldBackgroundColor: const Color(0xFFF5F7FB),
    textTheme: baseTextTheme.copyWith(
      displaySmall: baseTextTheme.displaySmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
      ),
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: colorScheme.surface,
      indicatorColor: colorScheme.primaryContainer,
      labelType: NavigationRailLabelType.none,
      selectedIconTheme: IconThemeData(color: colorScheme.primary),
      selectedLabelTextStyle: TextStyle(
        color: colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    ),
    navigationDrawerTheme: NavigationDrawerThemeData(
      tileHeight: 56,
      backgroundColor: colorScheme.surface,
      indicatorColor: colorScheme.primaryContainer,
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
  );
}
