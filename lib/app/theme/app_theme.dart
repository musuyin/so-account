import 'package:flutter/material.dart';

import '../../core/appearance.dart';

ThemeData appTheme(
  Brightness brightness, {
  AppPalette palette = AppPalette.cucumber,
}) {
  final dark = brightness == Brightness.dark;
  final seed = switch (palette) {
    AppPalette.cucumber => const Color(0xFF426638),
    AppPalette.sky => const Color(0xFF466E96),
    AppPalette.lavender => const Color(0xFF806591),
    AppPalette.classic => const Color(0xFFAB4523),
  };
  final colors = ColorScheme.fromSeed(seedColor: seed, brightness: brightness)
      .copyWith(
        primary: dark ? Color.lerp(seed, Colors.white, .58)! : seed,
        surface: dark ? const Color(0xFF141414) : const Color(0xFFF5F5F5),
        surfaceContainerLow: dark ? const Color(0xFF202020) : Colors.white,
      );
  OutlineInputBorder inputBorder(BorderSide side) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: side,
  );
  const small = TextStyle(fontFamily: 'NotoSansSC', fontSize: 11);
  const body = TextStyle(fontFamily: 'NotoSansSC', fontSize: 13);
  const title = TextStyle(
    fontFamily: 'NotoSansSC',
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );
  return ThemeData(
    textTheme: const TextTheme(
      displayLarge: title,
      displayMedium: title,
      displaySmall: title,
      headlineLarge: title,
      headlineMedium: title,
      headlineSmall: title,
      titleLarge: title,
      titleMedium: TextStyle(
        fontFamily: 'NotoSansSC',
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: body,
      bodyLarge: body,
      bodyMedium: body,
      bodySmall: small,
      labelLarge: body,
      labelMedium: small,
      labelSmall: small,
    ),
    fontFamily: 'NotoSansSC',
    useMaterial3: true,
    visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    dividerTheme: DividerThemeData(
      color: colors.outlineVariant.withValues(alpha: .45),
      space: 12,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      backgroundColor: colors.surface,
      elevation: 0,
      indicatorColor: colors.secondaryContainer,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          fontFamily: 'NotoSansSC',
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: colors.onSurfaceVariant,
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      extendedSizeConstraints: const BoxConstraints.tightFor(height: 48),
      elevation: 0,
      highlightElevation: 0,
      focusElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: colors.primaryContainer,
      foregroundColor: colors.onPrimaryContainer,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(color: colors.outlineVariant.withValues(alpha: .5)),
      selectedColor: colors.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    ),
    appBarTheme: AppBarTheme(
      toolbarHeight: 48,
      titleTextStyle: TextStyle(
        fontFamily: 'NotoSansSC',
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: colors.onSurface,
      ),
      backgroundColor: colors.surface,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      margin: const EdgeInsets.symmetric(vertical: 3),
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    listTileTheme: const ListTileThemeData(
      minTileHeight: 56,
      horizontalTitleGap: 10,
      minVerticalPadding: 6,
      contentPadding: EdgeInsets.symmetric(horizontal: 12),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: dark
          ? colors.surfaceContainerLow
          : Colors.white.withValues(alpha: .75),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: inputBorder(BorderSide.none),
      enabledBorder: inputBorder(BorderSide.none),
      disabledBorder: inputBorder(BorderSide.none),
      focusedBorder: inputBorder(BorderSide(color: colors.primary, width: 1.5)),
      errorBorder: inputBorder(BorderSide(color: colors.error)),
      focusedErrorBorder: inputBorder(
        BorderSide(color: colors.error, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );
}
