import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/audio_player_handler.dart';
import '../services/auth_service.dart';
import '../services/player_settings_service.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  final User user;
  final AudioPlayerHandler audioHandler;
  final VoidCallback? onRefreshRequired;

  const SettingsScreen({
    super.key,
    required this.user,
    required this.audioHandler,
    this.onRefreshRequired,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ApiService _apiService = ApiService();
  String _cacheSize = 'Подсчет...';
  bool _isCheckingUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    final size = await widget.audioHandler.cacheService.getFormattedCacheSize();
    if (mounted) {
      setState(() => _cacheSize = size);
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bg2,
        title: const Text('Очистить кэш музыки?', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          'Все сохраненные для мгновенного и бесшовного воспроизведения файлы треков будут удалены с устройства.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена', style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Очистить', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.audioHandler.cacheService.clearCache();
      await _loadCacheSize();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Кэш музыки успешно очищен')),
        );
      }
    }
  }

  void _showSoundCloudDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bg1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.cloud_sync_rounded, color: Color(0xFFFF7700), size: 28),
            SizedBox(width: 12),
            Text('SoundCloud', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.textPrimary)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Введите ссылку на ваш профиль SoundCloud или никнейм для синхронизации музыки:',
              style: TextStyle(fontSize: 13.5, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'https://soundcloud.com/username',
                hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                filled: true,
                fillColor: AppTheme.bg2,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFFF7700))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF7700)),
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Запуск синхронизации SoundCloud...')),
              );
              try {
                await _apiService.connectSoundCloud(text);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('SoundCloud успешно подключен!'), backgroundColor: AppTheme.accent),
                  );
                  widget.onRefreshRequired?.call();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.redAccent),
                  );
                }
              }
            },
            child: const Text('Синхронизировать', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _checkUpdates() async {
    setState(() => _isCheckingUpdate = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Проверка обновлений на GitHub...'), duration: Duration(seconds: 2)),
    );

    try {
      final update = await UpdateService().checkForUpdate();
      if (!mounted) return;
      if (update != null) {
        _showUpdateDialog(update);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('У вас установлена актуальная версия (v${UpdateService.currentVersion})')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCheckingUpdate = false);
    }
  }

  void _showUpdateDialog(UpdateInfo update) {
    double? downloadProgress;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.bg1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Доступна версия ${update.version}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (update.formattedSize.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text('Размер обновления: ${update.formattedSize}', style: const TextStyle(fontSize: 12, color: AppTheme.accentLight, fontWeight: FontWeight.bold)),
                ),
              Text(update.changelog, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              if (downloadProgress != null) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: downloadProgress, backgroundColor: AppTheme.bg3, color: AppTheme.accent),
                const SizedBox(height: 6),
                Text('Загрузка: ${(downloadProgress! * 100).toInt()}%', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              ],
            ],
          ),
          actions: [
            if (downloadProgress == null)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Позже', style: TextStyle(color: AppTheme.textMuted)),
              ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
              onPressed: downloadProgress != null
                  ? null
                  : () async {
                      setDialogState(() => downloadProgress = 0.0);
                      try {
                        await UpdateService().downloadAndInstall(
                          update,
                          onProgress: (progress) {
                            setDialogState(() => downloadProgress = progress);
                          },
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setDialogState(() => downloadProgress = null);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Ошибка обновления: $e'), backgroundColor: Colors.redAccent),
                          );
                        }
                      }
                    },
              child: Text(downloadProgress != null ? 'Загрузка...' : 'Обновить сейчас', style: const TextStyle(color: AppTheme.accentText)),
            ),
          ],
        ),
      ),
    );
  }

  void _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bg2,
        title: const Text('Выйти из аккаунта?', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('Вы сможете войти заново в любой момент.', style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена', style: TextStyle(color: AppTheme.textMuted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Выйти', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.audioHandler.stop();
      await AuthService().logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => LoginScreen(audioHandler: widget.audioHandler)),
        (route) => false,
      );
    }
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: AppTheme.textMuted,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg0,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Настройки',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // Карточка пользователя
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.bg2,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.bg4),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppTheme.accent,
                  child: ClipOval(
                    child: widget.user.fullAvatarUrl != null
                        ? CachedNetworkImage(
                            imageUrl: widget.user.fullAvatarUrl!,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Center(
                              child: Text(
                                widget.user.displayName.characters.firstOrNull?.toUpperCase() ?? 'U',
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.accentText),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              widget.user.displayName.characters.firstOrNull?.toUpperCase() ?? 'U',
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.accentText),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.user.displayName,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.user.username != null)
                        Text(
                          '@${widget.user.username!.replaceFirst('@', '')}',
                          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Раздел: Стиль экрана плеера
          _buildSectionHeader('Внешний вид и плеер'),
          ValueListenableBuilder<PlayerStyle>(
            valueListenable: PlayerSettingsService.playerStyleNotifier,
            builder: (context, currentStyle, _) {
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: currentStyle == PlayerStyle.djx ? const Color(0xFF00FF66).withAlpha(40) : AppTheme.bg3,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.album_rounded, color: Color(0xFF00FF66), size: 20),
                      ),
                      title: const Text(
                        'DJX-4000 (Виниловая вертушка)',
                        style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary, fontSize: 14),
                      ),
                      subtitle: const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Вращающийся винил, тонарм, CRT-дисплей трека, DJ-кнопки SYNC/CUE/LOOP и ползунок громкости.',
                          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ),
                      trailing: Icon(
                        currentStyle == PlayerStyle.djx ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                        color: currentStyle == PlayerStyle.djx ? const Color(0xFF00FF66) : AppTheme.textMuted,
                      ),
                      onTap: () => PlayerSettingsService.setPlayerStyle(PlayerStyle.djx),
                    ),
                    const Divider(height: 1, indent: 56, color: AppTheme.bg4),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: currentStyle == PlayerStyle.native ? Colors.blueAccent.withAlpha(40) : AppTheme.bg3,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.phone_android_rounded, color: Colors.blueAccent, size: 20),
                      ),
                      title: const Text(
                        'Стандартный плеер (Material You)',
                        style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary, fontSize: 14),
                      ),
                      subtitle: const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Классический минималистичный Android-дизайн приложения.',
                          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ),
                      trailing: Icon(
                        currentStyle == PlayerStyle.native ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                        color: currentStyle == PlayerStyle.native ? AppTheme.accent : AppTheme.textMuted,
                      ),
                      onTap: () => PlayerSettingsService.setPlayerStyle(PlayerStyle.native),
                    ),
                  ],
                ),
              );
            },
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: PlayerSettingsService.scratchEnabledNotifier,
                  builder: (context, scratchEnabled, _) {
                    return SwitchListTile.adaptive(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      secondary: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: scratchEnabled ? const Color(0xFF00FF66).withAlpha(40) : AppTheme.bg3,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.touch_app_rounded, color: Color(0xFF00FF66), size: 20),
                      ),
                      title: const Text(
                        'Интерактивный скретч винила',
                        style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary, fontSize: 14),
                      ),
                      subtitle: const Text(
                        'Вращение и скретчинг пластинки пальцем на пульте DJX-4000',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                      activeTrackColor: const Color(0xFF00FF66),
                      value: scratchEnabled,
                      onChanged: (val) => PlayerSettingsService.setScratchEnabled(val),
                    );
                  },
                ),
                const Divider(height: 1, indent: 56, color: AppTheme.bg4),
                ValueListenableBuilder<bool>(
                  valueListenable: PlayerSettingsService.dynamicThemeNotifier,
                  builder: (context, dynamicTheme, _) {
                    return SwitchListTile.adaptive(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      secondary: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: dynamicTheme ? Colors.purpleAccent.withAlpha(40) : AppTheme.bg3,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.palette_rounded, color: Colors.purpleAccent, size: 20),
                      ),
                      title: const Text(
                        'Динамическая тема по обложке',
                        style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary, fontSize: 14),
                      ),
                      subtitle: const Text(
                        'Адаптивная подсветка и фоновые оттенки под цветовую гамму трека',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                      activeTrackColor: AppTheme.accent,
                      value: dynamicTheme,
                      onChanged: (val) => PlayerSettingsService.setDynamicThemeEnabled(val),
                    );
                  },
                ),
              ],
            ),
          ),

          // Раздел: Воспроизведение и кэш
          _buildSectionHeader('Память и воспроизведение'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.storage_rounded, color: Colors.cyanAccent),
                  title: const Text('Кэш музыки и предзагрузка', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  subtitle: Text('Занято: $_cacheSize • Бесшовный переход включен', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  trailing: TextButton(
                    onPressed: _clearCache,
                    child: const Text('Очистить', style: TextStyle(color: Colors.redAccent)),
                  ),
                ),
                const Divider(height: 1, indent: 56, color: AppTheme.bg4),
                ListTile(
                  leading: const Icon(Icons.battery_charging_full_rounded, color: Colors.amber),
                  title: const Text('Фоновое воспроизведение', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  subtitle: const Text('Отключить ограничения батареи Android', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                  onTap: () {
                    const MethodChannel('ru.ganj4craft.aux/display').invokeMethod('requestIgnoreBatteryOptimizations');
                  },
                ),
                const Divider(height: 1, indent: 56, color: AppTheme.bg4),
                ListTile(
                  leading: const Icon(Icons.notifications_active_rounded, color: AppTheme.accentLight),
                  title: const Text('Шторка плеера и уведомления', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  subtitle: const Text('Настройки плеера на экране блокировки', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                  onTap: () {
                    const MethodChannel('ru.ganj4craft.aux/display').invokeMethod('openNotificationSettings');
                  },
                ),
              ],
            ),
          ),

          // Раздел: Импорт
          _buildSectionHeader('Импорт треков'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.cloud_sync_rounded, color: Color(0xFFFF7700)),
              title: const Text('Синхронизация с SoundCloud', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
              subtitle: const Text('Импорт плейлистов и треков из профиля SoundCloud', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
              onTap: _showSoundCloudDialog,
            ),
          ),

          // Раздел: О приложении и обновления
          _buildSectionHeader('О приложении'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.system_update_rounded, color: AppTheme.accentLight),
                  title: const Text('Обновление приложения', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  subtitle: const Text('Версия ${UpdateService.currentVersion} • Проверить обновления', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  trailing: _isCheckingUpdate
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent))
                      : const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                  onTap: _isCheckingUpdate ? null : _checkUpdates,
                ),
                const Divider(height: 1, indent: 56, color: AppTheme.bg4),
                ListTile(
                  leading: const Icon(Icons.send_rounded, color: AppTheme.accentLight),
                  title: const Text('Telegram-бот @auxbassbot', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  subtitle: const Text('Управление чатами, выгрузками и музыкой', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                  onTap: () async {
                    final uri = Uri.parse('tg://resolve?domain=auxbassbot');
                    if (!await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication)) {
                      await launchUrl(Uri.parse('https://t.me/auxbassbot'), mode: LaunchMode.externalApplication);
                    }
                  },
                ),
              ],
            ),
          ),

          // Раздел: Аккаунт
          _buildSectionHeader('Аккаунт'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
              title: const Text('Выйти из аккаунта', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.redAccent)),
              onTap: _logout,
            ),
          ),
        ],
      ),
    );
  }
}
