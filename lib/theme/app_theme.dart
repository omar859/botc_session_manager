import 'package:flutter/material.dart';
import 'appearance_controller.dart';

/// Central "futuristic emerald" design system. Every screen should pull
/// colors from here instead of hardcoding hex values, so a future
/// palette change is a one-file edit.
class AppColors {
  AppColors._();

  // Base surfaces — near-black with a faint green undertone rather
  // than pure grey, so the whole app reads as "one material" instead
  // of generic dark-mode grey.
  static const Color bgDeep = Color(0xFF07120E); // app background
  static const Color bgSurface = Color(0xFF0C1A15); // app bar / bottom nav
  static const Color bgCard = Color(0xFF11221C); // cards, sheets, tiles
  static const Color bgCardRaised = Color(0xFF16281F); // hover/expanded state

  // Emerald accent family
  static const Color emerald = Color(0xFF00E39B);
  static const Color emeraldDim = Color(0xFF00A876);
  static const Color emeraldGlow = Color(0x3300E39B); // for shadows/glows

  // Hairline separators — the "thin white strip" between sections.
  static const Color hairline = Color(0x1FFFFFFF); // ~12% white
  static const Color hairlineBright =
      Color(0x33FFFFFF); // ~20% white, for active states

  // Text
  static const Color textPrimary = Color(0xFFEAF6F1);
  static const Color textSecondary = Color(0xFF8FA69C);

  // Status (kept semantic, not re-themed — red/orange must stay legible)
  static const Color danger = Color(0xFFEF5350);
  static const Color warn = Color(0xFFFFB300);
  static const Color ok = emerald;
}

ThemeData buildAppTheme({
  AppThemeMode mode = AppThemeMode.defaultTheme,
  AppAccent accent = AppAccent.green,
}) {
  final isWhite = mode == AppThemeMode.white;
  final isDark = mode == AppThemeMode.dark;
  final accentColor = Color(accent.value);
  final background = isWhite
      ? const Color(0xFFF4F6F8)
      : isDark
          ? const Color(0xFF050609)
          : AppColors.bgDeep;
  final surface = isWhite
      ? Colors.white
      : isDark
          ? const Color(0xFF0D1016)
          : AppColors.bgSurface;
  final card = isWhite
      ? Colors.white
      : isDark
          ? const Color(0xFF151A22)
          : AppColors.bgCard;
  final primaryText = isWhite ? const Color(0xFF18212B) : AppColors.textPrimary;
  final secondaryText =
      isWhite ? const Color(0xFF5F6B78) : AppColors.textSecondary;
  final hairline = isWhite ? const Color(0x22000000) : AppColors.hairline;
  final brightness = isWhite ? Brightness.light : Brightness.dark;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: background,
    primaryColor: accentColor,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: accentColor,
      onPrimary: isWhite ? Colors.white : Colors.black,
      secondary: accentColor,
      onSecondary: isWhite ? Colors.white : Colors.black,
      surface: card,
      onSurface: primaryText,
      error: AppColors.danger,
      onError: Colors.white,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: primaryText,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
      iconTheme: IconThemeData(color: primaryText),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: accentColor.withOpacity(0.18),
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? accentColor : secondaryText,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(color: selected ? accentColor : secondaryText);
      }),
    ),
    dividerTheme: DividerThemeData(
      color: hairline,
      thickness: 1,
      space: 1,
    ),
    cardTheme: CardTheme(
      color: card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: hairline, width: 1),
      ),
    ),
    listTileTheme: ListTileThemeData(
      textColor: primaryText,
      iconColor: secondaryText,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: accentColor,
        side: BorderSide(color: hairline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accentColor,
        foregroundColor: isWhite ? Colors.white : Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      labelStyle: TextStyle(color: secondaryText),
      hintStyle: TextStyle(color: secondaryText),
      prefixIconColor: secondaryText,
      suffixIconColor: secondaryText,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: accentColor, width: 1.5),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: card,
      contentTextStyle: TextStyle(color: primaryText),
      actionTextColor: accentColor,
    ),
    textTheme: const TextTheme().apply(
      bodyColor: primaryText,
      displayColor: primaryText,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? accentColor.withOpacity(0.2)
                : card),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? accentColor
                : secondaryText),
        side: WidgetStateProperty.all(BorderSide(color: hairline)),
      ),
    ),
  );
}

/// Thin bright-white divider strip — the visual signature you asked
/// for, used between tab sections, above the bottom nav, and anywhere
/// content needs a crisp horizontal break instead of a plain gap.
class HairlineStrip extends StatelessWidget {
  final double opacity;
  const HairlineStrip({super.key, this.opacity = 1});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            Colors.white.withOpacity(0.35 * opacity),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}
