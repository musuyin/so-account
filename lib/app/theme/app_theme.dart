import 'package:flutter/material.dart';

import '../../core/appearance.dart';
import 'botanical_surfaces.dart';

ThemeData appTheme(
  Brightness brightness, {
  AppPalette palette = AppPalette.cucumber,
  BotanicalArt? art,
}) {
  final dark = brightness == Brightness.dark;
  final summer = palette == AppPalette.cucumber;
  final cool = palette == AppPalette.sky || palette == AppPalette.lavender;
  final seed = switch (palette) {
    AppPalette.cucumber => const Color(0xFF507348),
    AppPalette.sky => const Color(0xFF466E96),
    AppPalette.lavender => const Color(0xFF806591),
    AppPalette.classic =>
      dark ? const Color(0xFF82AAFF) : const Color(0xFFC65931),
  };
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness)
      .copyWith(
        surface: summer
            ? (dark ? const Color(0xFF121612) : const Color(0xFFF7F9EF))
            : dark
            ? const Color(0xFF121212)
            : const Color(0xFFFFF8F0),
        primary: cool
            ? (dark ? Color.lerp(seed, Colors.white, .6)! : seed)
            : summer
            ? (dark ? const Color(0xFFAFD29F) : const Color(0xFF426638))
            : dark
            ? const Color(0xFF91B6FF)
            : const Color(0xFFAB4523),
        secondary: cool
            ? (dark ? const Color(0xFFB9CACC) : const Color(0xFF55777A))
            : summer
            ? (dark ? const Color(0xFFDCD58F) : const Color(0xFF706522))
            : dark
            ? const Color(0xFF8BD5AC)
            : const Color(0xFF9A6200),
        tertiary: cool
            ? (dark ? const Color(0xFFE3C2CD) : const Color(0xFF906078))
            : summer
            ? (dark ? const Color(0xFFA5CFCA) : const Color(0xFF396B65))
            : dark
            ? const Color(0xFFC5A3FF)
            : const Color(0xFFAD303E),
      );
  final paletteColors = summer
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
  final colors = dark
      ? paletteColors
      : paletteColors.copyWith(
          surface: const Color(0xFFF5F5F5),
          primary: Color.lerp(paletteColors.primary, Colors.white, .08),
          secondary: Color.lerp(paletteColors.secondary, Colors.white, .08),
          tertiary: Color.lerp(paletteColors.tertiary, Colors.white, .08),
          primaryContainer: Color.lerp(
            paletteColors.primaryContainer,
            Colors.white,
            .3,
          ),
          secondaryContainer: Color.lerp(
            paletteColors.secondaryContainer,
            Colors.white,
            .3,
          ),
          surfaceContainer: Color.lerp(
            paletteColors.surfaceContainer,
            Colors.white,
            .4,
          ),
          surfaceContainerLow: Color.lerp(
            paletteColors.surfaceContainerLow,
            Colors.white,
            .4,
          ),
          surfaceContainerHighest: Color.lerp(
            paletteColors.surfaceContainerHighest,
            Colors.white,
            .4,
          ),
        );
  OutlineInputBorder inputBorder(BorderSide side) => summer && art != null
      ? BotanicalInputBorder(
          image: art.small,
          opacity: dark ? .06 : .22,
          borderSide: side,
        )
      : OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: side,
        );
  const small = TextStyle(fontFamily: 'NotoSansSC', fontSize: 12);
  const body = TextStyle(fontFamily: 'NotoSansSC', fontSize: 14);
  const title = TextStyle(
    fontFamily: 'NotoSansSC',
    fontSize: 20,
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
      titleMedium: body,
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
        fontSize: 20,
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
      color: cool
          ? (dark
                ? colors.surfaceContainerLow
                : colors.primaryContainer.withValues(alpha: .4))
          : summer
          ? (dark ? const Color(0xFF20271F) : const Color(0xFFF1F5E8))
          : dark
          ? const Color(0xFF202024)
          : const Color(0xFFFFF4EA),
      shape: summer && art != null
          ? BotanicalCardBorder(image: art.large, opacity: dark ? .055 : .23)
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
