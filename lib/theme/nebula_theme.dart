import 'package:flutter/material.dart';

class NebulaTheme {
  NebulaTheme._();

  static const Color primary = Color(0xFF6750A4);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFFEADDFF);
  static const Color onPrimaryContainer = Color(0xFF21005D);

  static const Color secondary = Color(0xFF006A6A);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFFCCEAEA);
  static const Color onSecondaryContainer = Color(0xFF002020);

  static const Color tertiary = Color(0xFF7D5260);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color tertiaryContainer = Color(0xFFFFD8E4);
  static const Color onTertiaryContainer = Color(0xFF31111D);

  static const Color background = Color(0xFF141218);
  static const Color onBackground = Color(0xFFE6E1E5);

  static const Color surface = Color(0xFF1C1B1F);
  static const Color onSurface = Color(0xFFE6E1E5);

  static const Color surfaceContainerLowest = Color(0xFF0F0D13);
  static const Color surfaceContainerLow = Color(0xFF1D1B20);
  static const Color surfaceContainer = Color(0xFF211F26);
  static const Color surfaceContainerHigh = Color(0xFF2B2930);
  static const Color surfaceContainerHighest = Color(0xFF36343B);

  static const Color outline = Color(0xFF938F99);
  static const Color outlineVariant = Color(0xFF49454F);

  static const Color error = Color(0xFFF2B8B5);
  static const Color onError = Color(0xFF601410);

  // Light theme colors
  static const Color lightPrimary = Color(0xFF6750A4);
  static const Color lightOnPrimary = Color(0xFFFFFFFF);
  static const Color lightPrimaryContainer = Color(0xFFEADDFF);
  static const Color lightOnPrimaryContainer = Color(0xFF21005D);

  static const Color lightSecondary = Color(0xFF006A6A);
  static const Color lightOnSecondary = Color(0xFFFFFFFF);
  static const Color lightSecondaryContainer = Color(0xFFCCEAEA);
  static const Color lightOnSecondaryContainer = Color(0xFF002020);

  static const Color lightTertiary = Color(0xFF7D5260);
  static const Color lightOnTertiary = Color(0xFFFFFFFF);
  static const Color lightTertiaryContainer = Color(0xFFFFD8E4);
  static const Color lightOnTertiaryContainer = Color(0xFF31111D);

  static const Color lightBackground = Color(0xFFFFFBFE);
  static const Color lightOnBackground = Color(0xFF1C1B1F);

  static const Color lightSurface = Color(0xFFFFFBFE);
  static const Color lightOnSurface = Color(0xFF1C1B1F);

  static const Color lightSurfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color lightSurfaceContainerLow = Color(0xFFF7F2FA);
  static const Color lightSurfaceContainer = Color(0xFFF3EDF7);
  static const Color lightSurfaceContainerHigh = Color(0xFFECE6F0);
  static const Color lightSurfaceContainerHighest = Color(0xFFE6E0EA);

  static const Color lightOutline = Color(0xFF79747E);
  static const Color lightOutlineVariant = Color(0xFFC4C0C8);

  static const Color lightError = Color(0xFFB3261E);
  static const Color lightOnError = Color(0xFFFFFFFF);

  static final BorderRadius shapeSmall = BorderRadius.circular(12);
  static final BorderRadius shapeMedium = BorderRadius.circular(20);
  static final BorderRadius shapeLarge = BorderRadius.circular(28);
  static final BorderRadius shapeExtraLarge = BorderRadius.circular(36);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primaryContainer,
        onPrimaryContainer: onPrimaryContainer,
        secondary: secondary,
        onSecondary: onSecondary,
        secondaryContainer: secondaryContainer,
        onSecondaryContainer: onSecondaryContainer,
        tertiary: tertiary,
        onTertiary: onTertiary,
        tertiaryContainer: tertiaryContainer,
        onTertiaryContainer: onTertiaryContainer,
        surface: surface,
        onSurface: onSurface,
        error: error,
        onError: onError,
        outline: outline,
        outlineVariant: outlineVariant,
      ),
      scaffoldBackgroundColor: background,
      fontFamily: 'Roboto',
      cardTheme: CardThemeData(
        color: surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: shapeLarge),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceContainerHigh,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: shapeExtraLarge),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceContainerHigh,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: shapeMedium),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: shapeMedium),
      ),
      dividerTheme: const DividerThemeData(
        color: outlineVariant,
        space: 1,
        thickness: 1,
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: lightPrimary,
        onPrimary: lightOnPrimary,
        primaryContainer: lightPrimaryContainer,
        onPrimaryContainer: lightOnPrimaryContainer,
        secondary: lightSecondary,
        onSecondary: lightOnSecondary,
        secondaryContainer: lightSecondaryContainer,
        onSecondaryContainer: lightOnSecondaryContainer,
        tertiary: lightTertiary,
        onTertiary: lightOnTertiary,
        tertiaryContainer: lightTertiaryContainer,
        onTertiaryContainer: lightOnTertiaryContainer,
        surface: lightSurface,
        onSurface: lightOnSurface,
        error: lightError,
        onError: lightOnError,
        outline: lightOutline,
        outlineVariant: lightOutlineVariant,
      ),
      scaffoldBackgroundColor: lightBackground,
      fontFamily: 'Roboto',
      cardTheme: CardThemeData(
        color: lightSurfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: shapeLarge),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: lightSurfaceContainerHigh,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: shapeExtraLarge),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: lightSurfaceContainerHigh,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: shapeMedium),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: shapeMedium),
      ),
      dividerTheme: const DividerThemeData(
        color: lightOutlineVariant,
        space: 1,
        thickness: 1,
      ),
    );
  }
}
