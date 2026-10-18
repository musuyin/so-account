import 'package:flutter/material.dart';

ThemeData appTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: dark ? const Color(0xFF82AAFF) : const Color(0xFFC65931),
        brightness: brightness,
      ).copyWith(
        surface: dark ? const Color(0xFF121212) : const Color(0xFFFFF8F0),
        primary: dark ? const Color(0xFF91B6FF) : const Color(0xFFAB4523),
        secondary: dark ? const Color(0xFF8BD5AC) : const Color(0xFF9A6200),
        tertiary: dark ? const Color(0xFFC5A3FF) : const Color(0xFFAD303E),
      );
  return ThemeData(
    fontFamily: 'NotoSansSC',
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xFF202024) : const Color(0xFFFFEEDF),
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
