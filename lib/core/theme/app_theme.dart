import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'app_colors.dart';

/// Port of `src/components/ModalStyles.ts` + helpers SPACING + responsive utils.
class AppSpacing {
  AppSpacing._();
  static const double sectionMargin = 10;
  static const double cardPadding = 16;
  static const double screenPadding = 10;
  static const double horizontalMargin = 10;
  static const double formHorizontal = 16;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
}

/// Responsive helpers — port of `src/utils/helpers.ts` wp/hp/normalize.
class Responsive {
  static double wp(BuildContext context, double percent) =>
      MediaQuery.of(context).size.width * percent / 100;
  static double hp(BuildContext context, double percent) =>
      MediaQuery.of(context).size.height * percent / 100;
  static double normalize(BuildContext context, double size) {
    final w = MediaQuery.of(context).size.width;
    final clampedW = w > 500 ? 500.0 : w;
    return size * clampedW / 375;
  }
  static double font(BuildContext context, double base) {
    final w = MediaQuery.of(context).size.width;
    if (w < 320) return base * 0.85;
    if (w < 375) return base * 0.95;
    if (w > 414) return base * 1.1;
    return base;
  }

  static bool get isWeb => kIsWeb;

  /// Returns true when the current screen should render the desktop/tablet layout.
  ///
  /// On mobile devices (Android / iOS), a phone rotated into landscape mode has a
  /// width > 768 dp but a [shortestSide] < 600 dp. By checking [shortestSide] on
  /// mobile platforms, phones in landscape orientation remain on the mobile layout,
  /// while tablets (iPad / Android tablets) and desktop platforms switch to the desktop shell.
  static bool isDesktop(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    if (media == null) return false;
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      return media.size.shortestSide >= 600 && media.size.width >= 768;
    }
    return media.size.width >= 768;
  }

  static bool isLargeScreen(BuildContext context) => isDesktop(context);
}

ThemeData buildDarkAppTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.primary,
    secondary: AppColors.secondary,
    tertiary: AppColors.accent,
    surface: Color(0xFF0A1F1F),
    error: AppColors.error,
    onPrimary: Colors.white,
    onSecondary: Colors.white,
    onSurface: Colors.white,
    onError: Colors.white,
  );
  return ThemeData(
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
      },
    ),
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF0A1F1F),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: Colors.white,
    ),
    cardTheme: CardThemeData(
      color: const Color.fromRGBO(255, 255, 255, 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color.fromRGBO(255, 255, 255, 0.1)),
      ),
      margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.horizontalMargin, vertical: 6),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color.fromRGBO(255, 255, 255, 0.05),
      hintStyle: const TextStyle(color: Color(0xFF666666)),
      labelStyle: const TextStyle(color: Color(0xFFA0D8D8)),
      prefixIconColor: const Color(0xFFA0D8D8),
      suffixIconColor: const Color(0xFFA0D8D8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color.fromRGBO(255, 255, 255, 0.1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color.fromRGBO(255, 255, 255, 0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.primary,
      selectionColor: Color.fromRGBO(76, 175, 80, 0.3),
      selectionHandleColor: AppColors.primary,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.buttonPrimary,
        foregroundColor: AppColors.buttonPrimaryText,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xF20A1F1F),
      selectedItemColor: AppColors.primary,
      unselectedItemColor: Color(0xFFA0D8D8),
      type: BottomNavigationBarType.fixed,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF061818),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFF061818),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(color: Colors.white),
      displayMedium: TextStyle(color: Colors.white),
      bodyLarge: TextStyle(color: Colors.white),
      bodyMedium: TextStyle(color: Colors.white),
      bodySmall: TextStyle(color: Color(0xFFA0D8D8)),
      labelSmall: TextStyle(color: Color(0xFF666666)),
    ),
    iconTheme: const IconThemeData(color: Colors.white),
    // Desktop interaction polish: visible hover tint on every InkWell/Widget
    // hoverable, a keyboard focus ring, and custom overlay scrollbars.
    hoverColor: const Color.fromRGBO(76, 175, 80, 0.10),
    focusColor: const Color.fromRGBO(76, 175, 80, 0.35),
    highlightColor: const Color.fromRGBO(76, 175, 80, 0.14),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.dragged)) {
          return const Color.fromRGBO(255, 255, 255, 0.60);
        }
        if (states.contains(WidgetState.hovered)) {
          return const Color.fromRGBO(255, 255, 255, 0.45);
        }
        return const Color.fromRGBO(255, 255, 255, 0.28);
      }),
      thickness: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered) ? 9.0 : 7.0),
      radius: const Radius.circular(8),
      minThumbLength: 48,
      mainAxisMargin: 6,
      crossAxisMargin: 2,
    ),
  );
}

ThemeData buildLightAppTheme() {
  const scheme = ColorScheme.light(
    primary: AppColors.primary,
    secondary: AppColors.secondary,
    tertiary: AppColors.accent,
    surface: Color(0xFFFFFFFF),
    error: AppColors.error,
    onPrimary: Colors.white,
    onSecondary: Colors.white,
    onSurface: Color(0xFF142424),
    onError: Colors.white,
  );
  return ThemeData(
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
      },
    ),
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF4F7F6),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: Color(0xFF142424),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFDCE3E3)),
      ),
      margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.horizontalMargin, vertical: 6),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      hintStyle: const TextStyle(color: Color(0xFF889B9B)),
      labelStyle: const TextStyle(color: Color(0xFF4D6E6E)),
      prefixIconColor: const Color(0xFF4D6E6E),
      suffixIconColor: const Color(0xFF4D6E6E),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFDCE3E3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFDCE3E3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.primary,
      selectionColor: Color.fromRGBO(76, 175, 80, 0.25),
      selectionHandleColor: AppColors.primary,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.buttonPrimary,
        foregroundColor: AppColors.buttonPrimaryText,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: Color(0xFF4D6E6E),
      type: BottomNavigationBarType.fixed,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(color: Color(0xFF142424)),
      displayMedium: TextStyle(color: Color(0xFF142424)),
      bodyLarge: TextStyle(color: Color(0xFF142424)),
      bodyMedium: TextStyle(color: Color(0xFF142424)),
      bodySmall: TextStyle(color: Color(0xFF4D6E6E)),
      labelSmall: TextStyle(color: Color(0xFF889B9B)),
    ),
    iconTheme: const IconThemeData(color: Color(0xFF142424)),
    // Desktop interaction polish (mirrored for the light theme)
    hoverColor: const Color.fromRGBO(76, 175, 80, 0.06),
    focusColor: const Color.fromRGBO(76, 175, 80, 0.28),
    highlightColor: const Color.fromRGBO(76, 175, 80, 0.10),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.dragged)) {
          return const Color(0x94006B5E);
        }
        if (states.contains(WidgetState.hovered)) {
          return const Color(0xA8006B5E);
        }
        return const Color.fromRGBO(20, 36, 36, 0.30);
      }),
      thickness: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered) ? 9.0 : 7.0),
      radius: const Radius.circular(8),
      minThumbLength: 48,
      mainAxisMargin: 6,
      crossAxisMargin: 2,
    ),
  );
}

ThemeData buildAppTheme() => AppColors.isDark ? buildDarkAppTheme() : buildLightAppTheme();

/// Monospace amount text style (matches OverviewScreen Courier usage).
class AmountText extends StatelessWidget {
  final String text;
  final double size;
  final Color? color;
  final FontWeight weight;
  const AmountText(this.text,
      {super.key, this.size = 16, this.color, this.weight = FontWeight.w600});
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          fontSize: size,
          color: color ?? AppColors.text,
          fontWeight: weight,
          fontFamilyFallback: const [
            'SF Pro Display',
            'SF Pro Text',
            'Apple Color Emoji',
            'sans-serif',
          ]));
}
