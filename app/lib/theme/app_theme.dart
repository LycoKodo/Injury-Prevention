import 'package:flutter/material.dart';

/// Dark, sporty "court" theme: lime/court-green accent on near-black surfaces.
class AppTheme {
  AppTheme._();

  static const Color courtGreen = Color(0xFFB6F000);
  static const Color courtGreenDim = Color(0xFF8FC400);
  static const Color surfaceDark = Color(0xFF0F1210);
  static const Color surfaceCard = Color(0xFF171C18);
  static const Color surfaceCardAlt = Color(0xFF1E241F);

  static const Color good = Color(0xFF4CD97B);
  static const Color warn = Color(0xFFFFC24B);
  static const Color danger = Color(0xFFFF5D5D);

  static const Map<String, Color> phaseColors = {
    'idle': Color(0xFF7C8B84),
    'preparation': Color(0xFF4BA3FF),
    'forward_swing': Color(0xFFB6F000),
    'contact': Color(0xFFFF5D5D),
    'follow_through': Color(0xFF9B6BFF),
  };

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: courtGreen,
      brightness: Brightness.dark,
    ).copyWith(
      primary: courtGreen,
      secondary: courtGreenDim,
      surface: surfaceDark,
      error: danger,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: surfaceDark,
      cardColor: surfaceCard,
      cardTheme: CardThemeData(
        color: surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: EdgeInsets.zero,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surfaceCard,
        selectedIconTheme: const IconThemeData(color: courtGreen),
        selectedLabelTextStyle: const TextStyle(color: courtGreen, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        indicatorColor: courtGreen.withValues(alpha: 0.16),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceDark,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      dividerColor: Colors.white.withValues(alpha: 0.08),
      textTheme: ThemeData.dark().textTheme.apply(
            bodyColor: Colors.white.withValues(alpha: 0.92),
            displayColor: Colors.white,
          ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: courtGreen,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceCardAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  /// Color for a 0..100 score. If [higherIsWorse] (e.g. injury risk), high values are red;
  /// otherwise (e.g. efficiency) high values are green.
  static Color scoreColor(num? value, {bool higherIsWorse = false}) {
    if (value == null) return Colors.grey;
    final v = value.toDouble();
    if (higherIsWorse) {
      if (v >= 66) return danger;
      if (v >= 33) return warn;
      return good;
    }
    if (v >= 66) return good;
    if (v >= 33) return warn;
    return danger;
  }

  static Color riskColor(num value) {
    if (value < 33) return good;
    if (value < 66) return warn;
    return danger;
  }

  static Color phaseColor(String? phase) {
    return phaseColors[phase] ?? phaseColors['idle']!;
  }
}
