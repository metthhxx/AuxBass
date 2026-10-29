import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PlayerStyle {
  djx,    // DJX-4000 Винил / Турнтабл с сайта
  native, // Стандартный плеер (Material You)
}

class PlayerSettingsService {
  static const String _key = 'auxbass_player_style';

  static final ValueNotifier<PlayerStyle> playerStyleNotifier =
      ValueNotifier<PlayerStyle>(PlayerStyle.djx);

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
    } catch (_) {}
  }

  static Future<void> setPlayerStyle(PlayerStyle style) async {
    playerStyleNotifier.value = style;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, style == PlayerStyle.native ? 'native' : 'djx');
    } catch (_) {}
  }
}
