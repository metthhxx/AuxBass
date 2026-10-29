import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PlayerStyle {
  native, // Стандартный плеер (Material You)
  web,    // Веб-стиль AuxBass (Неоморфизм / Cyber Glass)
}

class PlayerSettingsService {
  static const String _key = 'auxbass_player_style';

  static final ValueNotifier<PlayerStyle> playerStyleNotifier =
      ValueNotifier<PlayerStyle>(PlayerStyle.web);

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (saved == 'native') {
        playerStyleNotifier.value = PlayerStyle.native;
      } else if (saved == 'web') {
        playerStyleNotifier.value = PlayerStyle.web;
      } else {
        // По умолчанию веб-плеер, так как пользователь запросил веб-стиль
        playerStyleNotifier.value = PlayerStyle.web;
      }
    } catch (_) {}
  }

  static Future<void> setPlayerStyle(PlayerStyle style) async {
    playerStyleNotifier.value = style;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, style == PlayerStyle.web ? 'web' : 'native');
    } catch (_) {}
  }
}
