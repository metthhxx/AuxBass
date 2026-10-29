import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PlayerStyle {
  djx,    // DJX-4000 Винил / Турнтабл с сайта
  native, // Стандартный плеер (Material You)
}

class PlayerSettingsService {
  static const String _key = 'auxbass_player_style';
  static const String _keyScratch = 'auxbass_scratch_enabled';
  static const String _keyDynamicTheme = 'auxbass_dynamic_theme_enabled';

  static final ValueNotifier<PlayerStyle> playerStyleNotifier =
      ValueNotifier<PlayerStyle>(PlayerStyle.djx);

  static final ValueNotifier<bool> scratchEnabledNotifier =
      ValueNotifier<bool>(true);

  static final ValueNotifier<bool> dynamicThemeNotifier =
      ValueNotifier<bool>(true);

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (saved == 'native') {
        playerStyleNotifier.value = PlayerStyle.native;
      } else {
        // По умолчанию DJX-4000 с винилом и DJ-пультом
        playerStyleNotifier.value = PlayerStyle.djx;
      }

      scratchEnabledNotifier.value = prefs.getBool(_keyScratch) ?? true;
      dynamicThemeNotifier.value = prefs.getBool(_keyDynamicTheme) ?? true;
    } catch (_) {}
  }

  static Future<void> setPlayerStyle(PlayerStyle style) async {
    playerStyleNotifier.value = style;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, style == PlayerStyle.native ? 'native' : 'djx');
    } catch (_) {}
  }

  static Future<void> setScratchEnabled(bool enabled) async {
    scratchEnabledNotifier.value = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyScratch, enabled);
    } catch (_) {}
  }

  static Future<void> setDynamicThemeEnabled(bool enabled) async {
    dynamicThemeNotifier.value = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyDynamicTheme, enabled);
    } catch (_) {}
  }
}
