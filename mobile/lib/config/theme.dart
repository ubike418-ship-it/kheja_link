import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The Kheja_Link design language, ported from the web app so the two feel like
/// one product: blue-600 primary, a zinc neutral ramp, heavy rounded corners
/// and very bold, tightly tracked display type.
class KhejaColors {
  const KhejaColors._();

  static const blue = Color(0xFF2563EB);
  static const blueDark = Color(0xFF1D4ED8);
  static const emerald = Color(0xFF059669);
  static const purple = Color(0xFF9333EA);
  static const amber = Color(0xFFD97706);
  static const red = Color(0xFFDC2626);

  /// The dark ground of the logo — used for the splash and brand tiles.
  static const brandInk = Color(0xFF1B2430);

  static const zinc50 = Color(0xFFFAFAFA);
  static const zinc100 = Color(0xFFF4F4F5);
  static const zinc200 = Color(0xFFE4E4E7);
  static const zinc300 = Color(0xFFD4D4D8);
  static const zinc400 = Color(0xFFA1A1AA);
  static const zinc500 = Color(0xFF71717A);
  static const zinc600 = Color(0xFF52525B);
  static const zinc800 = Color(0xFF27272A);
  static const zinc900 = Color(0xFF18181B);
  static const black = Color(0xFF000000);
}

/// Corner radii. The web design leans on very large radii; these mirror it.
class KhejaRadius {
  const KhejaRadius._();

  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 44.0;
}

ThemeData buildKhejaTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;

  final surface = isDark ? KhejaColors.zinc900 : Colors.white;
  final background = isDark ? KhejaColors.black : KhejaColors.zinc50;
  final onSurface = isDark ? Colors.white : KhejaColors.zinc900;
  final muted = isDark ? KhejaColors.zinc400 : KhejaColors.zinc500;
  final border = isDark ? KhejaColors.zinc800 : KhejaColors.zinc200;

  final base = ThemeData(brightness: brightness, useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: KhejaColors.blue,
      brightness: brightness,
    ).copyWith(
      primary: KhejaColors.blue,
      onPrimary: Colors.white,
      surface: surface,
      onSurface: onSurface,
      outline: border,
      error: KhejaColors.red,
    ),
    textTheme: _textTheme(base.textTheme, onSurface, muted),
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle:
          isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      titleTextStyle: TextStyle(
        color: onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.6,
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KhejaRadius.xl),
        side: BorderSide(color: border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? KhejaColors.zinc800 : KhejaColors.zinc50,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      hintStyle: TextStyle(color: KhejaColors.zinc400, fontWeight: FontWeight.w500),
      border: _inputBorder(border),
      enabledBorder: _inputBorder(border),
      focusedBorder: _inputBorder(KhejaColors.blue, width: 1.6),
      errorBorder: _inputBorder(KhejaColors.red),
      focusedErrorBorder: _inputBorder(KhejaColors.red, width: 1.6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: KhejaColors.blue,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KhejaRadius.md),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.2,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: onSurface,
        minimumSize: const Size.fromHeight(56),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KhejaRadius.md),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: KhejaColors.blue,
        textStyle: const TextStyle(fontWeight: FontWeight.w900),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: isDark ? KhejaColors.zinc800 : KhejaColors.zinc100,
      side: BorderSide(color: border),
      labelStyle: TextStyle(
        color: onSurface,
        fontWeight: FontWeight.w800,
        fontSize: 13,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KhejaRadius.md),
      ),
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: surface,
      selectedItemColor: KhejaColors.blue,
      unselectedItemColor: KhejaColors.zinc400,
      selectedLabelStyle:
          const TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
      unselectedLabelStyle:
          const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? Colors.white : KhejaColors.zinc900,
      contentTextStyle: TextStyle(
        color: isDark ? KhejaColors.zinc900 : Colors.white,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KhejaRadius.md),
      ),
    ),
  );
}

OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(KhejaRadius.md),
    borderSide: BorderSide(color: color, width: width),
  );
}

TextTheme _textTheme(TextTheme base, Color onSurface, Color muted) {
  return base
      .copyWith(
        displayLarge: base.displayLarge?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: -2.4,
          height: 0.95,
        ),
        displaySmall: base.displaySmall?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: -1.6,
          height: 1.0,
        ),
        headlineMedium: base.headlineMedium?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: -1.2,
        ),
        headlineSmall: base.headlineSmall?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: -0.8,
        ),
        titleLarge: base.titleLarge?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: -0.6,
        ),
        titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        bodyLarge: base.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
        bodyMedium: base.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
        labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w900),
      )
      .apply(bodyColor: onSurface, displayColor: onSurface);
}

/// The all-caps, wide-tracked eyebrow label used throughout the web design.
const kEyebrowStyle = TextStyle(
  fontSize: 10,
  fontWeight: FontWeight.w900,
  letterSpacing: 2,
);
