import 'package:flutter/material.dart';

import '../../core/appearance.dart';

ThemeData appTheme(
  Brightness brightness, {
  AppPalette palette = AppPalette.classic,
}) {
  final dark = brightness == Brightness.dark;
  final summer = palette == AppPalette.cucumber;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: summer
            ? const Color(0xFF507348)
            : dark
            ? const Color(0xFF82AAFF)
            : const Color(0xFFC65931),
        brightness: brightness,
      ).copyWith(
        surface: summer
            ? (dark ? const Color(0xFF121612) : const Color(0xFFF7F9EF))
            : dark
            ? const Color(0xFF121212)
            : const Color(0xFFFFF8F0),
        primary: summer
            ? (dark ? const Color(0xFFAFD29F) : const Color(0xFF426638))
            : dark
            ? const Color(0xFF91B6FF)
            : const Color(0xFFAB4523),
        secondary: summer
            ? (dark ? const Color(0xFFDCD58F) : const Color(0xFF706522))
            : dark
            ? const Color(0xFF8BD5AC)
            : const Color(0xFF9A6200),
        tertiary: summer
            ? (dark ? const Color(0xFFA5CFCA) : const Color(0xFF396B65))
            : dark
            ? const Color(0xFFC5A3FF)
            : const Color(0xFFAD303E),
      );
  final colors = summer
      ? scheme.copyWith(
          primaryContainer: dark
              ? const Color(0xFF2C4828)
              : const Color(0xFFDDECCF),
          onPrimaryContainer: dark
              ? const Color(0xFFDDECCF)
              : const Color(0xFF173310),
          secondaryContainer: dark
              ? const Color(0xFF49441E)
              : const Color(0xFFF4EDBD),
          onSecondaryContainer: dark
              ? const Color(0xFFF4EDBD)
              : const Color(0xFF393209),
        )
      : scheme;
  return ThemeData(
    fontFamily: 'NotoSansSC',
    useMaterial3: true,
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: summer
          ? (dark ? const Color(0xFF20271F) : const Color(0xFFEDF3DF))
          : dark
          ? const Color(0xFF202024)
          : const Color(0xFFFFEEDF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(48, 50)),
    ),
  );
}
