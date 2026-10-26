import 'package:flutter/material.dart';

class AppTheme {
  // Фирменные цвета сайта aux.ganj4craft.ru + Material You 3
  static const Color accent = Color(0xFF1DB954);       // --c-accent
  static const Color accentLight = Color(0xFF1ED760);  // --c-accent-light
  static const Color accentDark = Color(0xFF169C46);   // --c-accent-dark
  static const Color accentGlow = Color(0x591DB954);   // --c-accent-glow rgba(29, 185, 84, 0.35)
  static const Color accentText = Color(0xFF000000);   // --c-accent-text

  // Material You 3 Dark Surfaces (с легким зеленым оттенком)
  static const Color bg0 = Color(0xFF0D0F0D);          // Основной глубокий фон
  static const Color bg1 = Color(0xFF131714);          // Surface container lowest
  static const Color bg2 = Color(0xFF1A211B);          // Surface container low / Card
  static const Color bg3 = Color(0xFF222B24);          // Surface container / Input
  static const Color bg4 = Color(0xFF2B362D);          // Surface container high / Border

  // Тексты
  static const Color textPrimary = Color(0xFFF1F5F1);  // High emphasis text
  static const Color textSecondary = Color(0xFFA5B2A7);// Medium emphasis text
  static const Color textMuted = Color(0xFF707E72);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg0,
      primaryColor: accent,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        onPrimary: accentText,
        secondary: accentLight,
        onSecondary: accentText,
        surface: bg0,
        surfaceContainerLow: bg1,
        surfaceContainer: bg2,
        surfaceContainerHigh: bg3,
        surfaceContainerHighest: bg4,
        onSurface: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bg0,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        dividerColor: Colors.transparent, // Полностью убирает полоску под табами!
        indicatorColor: accent,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: accentLight,
        unselectedLabelColor: textSecondary,
        labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.normal, fontSize: 14),
      ),
      cardTheme: CardThemeData(
        color: bg2,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: accentText,
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
