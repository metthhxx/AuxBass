import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/global_user.dart';
import '../models/paged_tracks.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/audio_player_handler.dart';
import '../services/auth_service.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/track_tile.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  final User user;
  final AudioPlayerHandler audioHandler;

  const HomeScreen({
    super.key,
    required this.user,
    required this.audioHandler,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _apiService = ApiService();
  int _currentNavIndex = 0;

  // Данные
  List<Track> _allTracks = [];
  int _totalLibraryTracks = 0;
  List<Track> _likedTracks = [];
  List<Track> _historyTracks = [];
  List<Track> _globalTracks = [];
  List<Playlist> _playlists = [];
  List<GlobalUser> _globalUsers = [];

  bool _isLoading = true;
  String? _errorMessage;

  // Поиск: фильтр источника (0 - Мои треки, 1 - Треки на сайте)
  int _searchSourceIndex = 0;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Серверный поиск по всем 4800+ трекам сайта
  List<Track> _serverSearchResults = [];
  bool _isSearchingServer = false;
  int _serverSearchTotal = 0;
  String _lastServerQuery = '';
  Timer? _searchDebounce;

  // Контроллер для свайпов между 5 вкладками
  late final PageController _pageController;

  // Библиотека: фильтр подкатегорий (0 - Все треки, 1 - Плейлисты, 2 - История)
  int _libraryFilterIndex = 0;

  // Подписки: подкатегория (0 - Пользователи, 1 - Telegram-каналы)
  int _subscriptionsFilterIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentNavIndex);
    _loadAllData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates(manual: false);
      _checkNotificationPermissionStatus();
    });
  }

  Future<void> _checkNotificationPermissionStatus() async {
    try {
      final bool? enabled = await const MethodChannel('ru.ganj4craft.aux/display')
          .invokeMethod('areNotificationsEnabled');
      if (enabled == false && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.bg2,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: const Text(
              'Для плеера в шторке включите уведомления',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
            action: SnackBarAction(
              label: 'Включить',
              textColor: AppTheme.accent,
              onPressed: () {
                const MethodChannel('ru.ganj4craft.aux/display')
                    .invokeMethod('openNotificationSettings');
              },
            ),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Быстро загружаем первую страницу каждого источника для мгновенного отклика
      final results = await Future.wait([
        _apiService.getLibraryTracksPage(page: 1, perPage: 100),
        _apiService.getHistoryTracks(),
        _apiService.getGlobalTracks(page: 1, perPage: 100),
        _apiService.getPlaylists(),
        _apiService.getGlobalUsers(),
      ]);

      final firstLib = results[0] as PagedTracks;

      if (mounted) {
        setState(() {
          _allTracks = List.from(firstLib.items);
          _totalLibraryTracks = firstLib.total;
          _historyTracks = results[1] as List<Track>;
          _globalTracks = results[2] as List<Track>;
          _playlists = results[3] as List<Playlist>;
          _globalUsers = results[4] as List<GlobalUser>;
          _isLoading = false;
        });
      }

      // 2. В фоне выкачиваем все остальные страницы библиотеки (до 1000+ треков) и лайков
      _loadAllRemainingPages();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  void _loadAllRemainingPages() {
    _apiService.getAllLibraryTracks(
      onProgress: (currentLoaded, total) {
        if (mounted) {
          setState(() {
            _allTracks = currentLoaded;
            _totalLibraryTracks = total;
          });
        }
      },
    );

    _apiService.getAllLikedTracks(
      onProgress: (currentLoaded, total) {
        if (mounted) {
          setState(() {
            _likedTracks = currentLoaded;
          });
        }
      },
    );
  }

  List<Track> _filterList(List<Track> list, String query) {
    if (query.isEmpty) return list;
    final q = query.toLowerCase();
    return list.where((t) => t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q)).toList();
  }

  /// Запуск случайного микса из всех 4800+ треков на сайте (Шафл по сайту)
  Future<void> _startGlobalShuffle() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🎲 Собираем случайный микс из всей базы AuxBass...'),
        duration: Duration(seconds: 2),
        backgroundColor: AppTheme.bg2,
      ),
    );
    try {
      final tracks = await _apiService.getRandomGlobalShuffle(count: 100);
      if (tracks.isNotEmpty) {
        widget.audioHandler.playTrackList(tracks, 0);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка шафла: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  /// Поиск по всем 4800+ трекам на сервере
  Future<void> _performServerSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _serverSearchResults = [];
        _serverSearchTotal = 0;
      });
      return;
    }
    _lastServerQuery = query;

    setState(() {
      _isSearchingServer = true;
    });

    try {
      final paged = await _apiService.searchGlobalTracks(query, page: 1, perPage: 100);
      if (mounted && _lastServerQuery == query) {
        setState(() {
          _serverSearchResults = paged.items;
          _serverSearchTotal = paged.total;
          _isSearchingServer = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSearchingServer = false;
        });
      }
    }
  }

  Widget _buildUserAvatar({
    required String? avatarUrl,
    required String displayName,
    required double radius,
    required double fontSize,
    Color? backgroundColor,
    Color? textColor,
  }) {
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';
    final bg = backgroundColor ?? AppTheme.accent;
    final fg = textColor ?? AppTheme.accentText;

    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      child: ClipOval(
        child: avatarUrl != null && avatarUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: avatarUrl,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                memCacheWidth: (radius * 4).toInt(),
                memCacheHeight: (radius * 4).toInt(),
                errorWidget: (_, __, ___) => Center(
                  child: Text(
                    initial,
                    style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold, color: fg),
                  ),
                ),
                placeholder: (_, __) => Center(
                  child: Text(
                    initial,
                    style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold, color: fg),
                  ),
                ),
              )
            : Center(
                child: Text(
                  initial,
                  style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold, color: fg),
                ),
              ),
      ),
    );
  }

  // ================= ПРОФИЛЬ & SOUNDCLOUD =================
  void _showProfileModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bg1,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        final user = widget.user;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildUserAvatar(
                  avatarUrl: user.fullAvatarUrl,
                  displayName: user.displayName,
                  radius: 44,
                  fontSize: 34,
                ),
                const SizedBox(height: 14),
                Text(
                  user.displayName,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                if (user.username != null) ...[
                  const SizedBox(height: 4),
                  Text('@${user.username}', style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
                ],
                const SizedBox(height: 20),

                // Статистика
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.bg2,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.bg4.withAlpha(100)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildProfileStat('Треков', _allTracks.length),
                      Container(width: 1, height: 28, color: AppTheme.bg4),
                      _buildProfileStat('Любимых', _likedTracks.length),
                      Container(width: 1, height: 28, color: AppTheme.bg4),
                      _buildProfileStat('Плейлистов', _playlists.length),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Кнопка синхронизации с SoundCloud
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5500).withAlpha(40),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.cloud_sync_rounded, color: Color(0xFFFF7700), size: 24),
                ),
                title: const Text('Синхронизация с SoundCloud', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                subtitle: const Text('Импорт треков и плейлистов из SoundCloud', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showSoundCloudDialog();
                },
              ),
              const SizedBox(height: 8),

              // Шторка плеера и уведомления
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withAlpha(35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.notifications_active_rounded, color: AppTheme.accentLight, size: 22),
                ),
                title: const Text('Шторка плеера и уведомления', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                subtitle: const Text('Настройки показа плеера в шторке Android', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                onTap: () {
                  Navigator.pop(ctx);
                  const MethodChannel('ru.ganj4craft.aux/display').invokeMethod('openNotificationSettings');
                },
              ),
              const SizedBox(height: 8),

              // Фоновое воспроизведение (Батарея)
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withAlpha(35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.battery_charging_full_rounded, color: Colors.amber, size: 22),
                ),
                title: const Text('Фоновое воспроизведение', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                subtitle: const Text('Отключить ограничения батареи при выключенном экране', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                onTap: () {
                  Navigator.pop(ctx);
                  const MethodChannel('ru.ganj4craft.aux/display').invokeMethod('requestIgnoreBatteryOptimizations');
                },
              ),
              const SizedBox(height: 8),

                // Кнопка перехода в бота
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withAlpha(35),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.send_rounded, color: AppTheme.accentLight, size: 22),
                  ),
                  title: const Text('Telegram-бот @auxbassbot', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  subtitle: const Text('Управление чатами и загрузками', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final uri = Uri.parse('tg://resolve?domain=auxbassbot');
                    if (!await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication)) {
                      await launchUrl(Uri.parse('https://t.me/auxbassbot'), mode: LaunchMode.externalApplication);
                    }
                  },
                ),
                const SizedBox(height: 8),

                // Проверка обновлений (OTA через GitHub Releases)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withAlpha(35),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.system_update_rounded, color: AppTheme.accentLight, size: 22),
                  ),
                  title: const Text('Обновление приложения', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  subtitle: const Text('Версия 1.0.2 • Проверить обновления', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _checkForUpdates(manual: true);
                  },
                ),
                const SizedBox(height: 16),

                // Кнопка выхода
                FilledButton.tonalIcon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await widget.audioHandler.stop();
                    await AuthService().logout();
                    if (!mounted) return;
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => LoginScreen(audioHandler: widget.audioHandler)),
                    );
                  },
                  icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                  label: const Text('Выйти из аккаунта', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent.withAlpha(25),
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
            Text('SoundCloud', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
                  _loadAllData();
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

  Widget _buildProfileStat(String label, int count) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.accentLight),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
      ],
    );
  }

  // ================= OTA ОБНОВЛЕНИЯ (GITHUB RELEASES) =================
  Future<void> _checkForUpdates({bool manual = false}) async {
    if (manual) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Проверяем обновления AuxBass на GitHub...'),
          duration: Duration(seconds: 2),
          backgroundColor: AppTheme.bg2,
        ),
      );
    }

    final update = await UpdateService().checkForUpdate();
    if (!mounted) return;

    if (update != null) {
      _showUpdateDialog(update);
    } else if (manual) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('У вас установлена последняя версия AuxBass (v1.0.0)'),
          backgroundColor: AppTheme.bg2,
        ),
      );
    }
  }

  void _showUpdateDialog(UpdateInfo update) {
    double? downloadProgress;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: AppTheme.bg1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                const Icon(Icons.system_update_rounded, color: AppTheme.accent, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Обновление ${update.version}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (update.formattedSize.isNotEmpty) ...[
                  Text('Размер: ${update.formattedSize}', style: const TextStyle(fontSize: 13, color: AppTheme.accentLight)),
                  const SizedBox(height: 10),
                ],
                const Text('Что нового:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.bg2,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      update.changelog,
                      style: const TextStyle(fontSize: 13, color: Colors.white, height: 1.4),
                    ),
                  ),
                ),
                if (downloadProgress != null) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: downloadProgress,
                    backgroundColor: AppTheme.bg3,
                    valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Скачивание: ${(downloadProgress! * 100).toInt()}%',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              if (downloadProgress == null) ...[
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Позже', style: TextStyle(color: AppTheme.textSecondary)),
                ),
                FilledButton(
                  onPressed: () async {
                    setDialogState(() => downloadProgress = 0.01);
                    try {
                      await UpdateService().downloadAndInstall(
                        update,
                        onProgress: (prog) {
                          setDialogState(() => downloadProgress = prog);
                        },
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      setDialogState(() => downloadProgress = null);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Ошибка загрузки: $e'), backgroundColor: Colors.redAccent),
                        );
                      }
                    }
                  },
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: AppTheme.accentText),
                  child: const Text('Обновить'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg0,
      appBar: AppBar(
        title: Text(_getTabTitle()),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary),
            tooltip: 'Обновить',
            onPressed: _loadAllData,
          ),
          GestureDetector(
            onTap: _showProfileModal,
            child: Container(
              margin: const EdgeInsets.only(right: 16, left: 6),
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.accent, width: 2),
                boxShadow: const [
                  BoxShadow(color: AppTheme.accentGlow, blurRadius: 10),
                ],
              ),
              child: _buildUserAvatar(
                avatarUrl: widget.user.fullAvatarUrl,
                displayName: widget.user.displayName,
                radius: 17,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppTheme.accent)))
                : _errorMessage != null
                    ? _buildErrorView()
                    : PageView(
                        controller: _pageController,
                        onPageChanged: (idx) => setState(() => _currentNavIndex = idx),
                        children: [
                          KeepAlivePage(child: _buildHomeTab()),
                          KeepAlivePage(child: _buildSearchTab()),
                          KeepAlivePage(child: _buildLibraryTab()),
                          KeepAlivePage(child: _buildFavoritesTab()),
                          KeepAlivePage(child: _buildSubscriptionsTab()),
                        ],
                      ),
          ),
          MiniPlayer(audioHandler: widget.audioHandler),
        ],
      ),

      // Material You 3 Нижняя панель навигации (5 кнопок)
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          height: 72,
          indicatorColor: AppTheme.accent.withAlpha(45),
          indicatorShape: const StadiumBorder(),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final isSelected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? AppTheme.accentLight : AppTheme.textSecondary,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final isSelected = states.contains(WidgetState.selected);
            return IconThemeData(
              size: 24,
              color: isSelected ? AppTheme.accentLight : AppTheme.textSecondary,
            );
          }),
        ),
        child: NavigationBar(
          backgroundColor: AppTheme.bg1,
          elevation: 0,
          selectedIndex: _currentNavIndex,
          onDestinationSelected: (idx) {
            setState(() => _currentNavIndex = idx);
            _pageController.animateToPage(
              idx,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
            );
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Главная',
            ),
            NavigationDestination(
              icon: Icon(Icons.search_rounded),
              selectedIcon: Icon(Icons.search_rounded),
              label: 'Поиск',
            ),
            NavigationDestination(
              icon: Icon(Icons.library_music_outlined),
              selectedIcon: Icon(Icons.library_music_rounded),
              label: 'Библиотека',
            ),
            NavigationDestination(
              icon: Icon(Icons.favorite_outline_rounded),
              selectedIcon: Icon(Icons.favorite_rounded),
              label: 'Любимые',
            ),
            NavigationDestination(
              icon: Icon(Icons.subscriptions_outlined),
              selectedIcon: Icon(Icons.subscriptions_rounded),
              label: 'Подписки',
            ),
          ],
        ),
      ),
    );
  }

  String _getTabTitle() {
    switch (_currentNavIndex) {
      case 0:
        return 'Главная';
      case 1:
        return 'Поиск';
      case 2:
        return 'Библиотека';
      case 3:
        return 'Любимые треки';
      case 4:
        return 'Подписки & Авторы';
      default:
        return 'AuxBass';
    }
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, color: Colors.redAccent, size: 54),
            const SizedBox(height: 14),
            Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 18),
            FilledButton.tonal(onPressed: _loadAllData, child: const Text('Повторить попытку')),
          ],
        ),
      ),
    );
  }

  // ================= 1. ГЛАВНАЯ =================
  Widget _buildHomeTab() {
    return RefreshIndicator(
      color: AppTheme.accent,
      backgroundColor: AppTheme.bg2,
      onRefresh: _loadAllData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF142417), Color(0xFF1B3120)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppTheme.accent.withAlpha(60)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Привет, ${widget.user.firstName ?? widget.user.displayName}!',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Ваша музыка из Telegram всегда с вами',
                        style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (_allTracks.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () {
                      final list = List<Track>.from(_allTracks)..shuffle();
                      widget.audioHandler.playTrackList(list, 0);
                    },
                    icon: const Icon(Icons.shuffle_rounded, size: 18),
                    label: const Text('Микс'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: AppTheme.accentText,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Кнопка-карточка "Шафл по всем трекам на сайте" как на сайте AuxBass
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF18311F), Color(0xFF122216)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppTheme.accent.withAlpha(80)),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withAlpha(40),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.casino_rounded, color: AppTheme.accentLight, size: 26),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Шафл по трекам на сайте',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Случайный микс из всей базы (4800+ треков)',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _startGlobalShuffle,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: AppTheme.accentText,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shuffle_rounded, size: 18),
                      SizedBox(width: 6),
                      Text('Шафл', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          const Text('🔥 Популярно в сети', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
          const SizedBox(height: 12),
          if (_globalTracks.isEmpty)
            const Text('Треки загружаются...', style: TextStyle(color: AppTheme.textMuted))
          else
            ..._globalTracks.take(8).map((track) {
              return ValueListenableBuilder<Track?>(
                valueListenable: widget.audioHandler.currentTrackNotifier,
                builder: (context, current, _) {
                  return TrackTile(
                    track: track,
                    isPlaying: current?.id == track.id,
                    onTap: () {
                      widget.audioHandler.playTrackList(_globalTracks, _globalTracks.indexOf(track));
                    },
                  );
                },
              );
            }),

          const SizedBox(height: 24),

          if (_historyTracks.isNotEmpty) ...[
            const Text('🕒 Недавно слушали', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            ..._historyTracks.take(5).map((track) {
              return ValueListenableBuilder<Track?>(
                valueListenable: widget.audioHandler.currentTrackNotifier,
                builder: (context, current, _) {
                  return TrackTile(
                    track: track,
                    isPlaying: current?.id == track.id,
                    onTap: () {
                      widget.audioHandler.playTrackList(_historyTracks, _historyTracks.indexOf(track));
                    },
                  );
                },
              );
            }),
          ],
        ],
      ),
    );
  }

  // ================= 2. ПОИСК (РАЗДЕЛЕН НА МОИ ТРЕКИ И НА САЙТЕ) =================
  Widget _buildSearchTab() {
    return Column(
      children: [
        // Поле поиска
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SearchBar(
            controller: _searchController,
            onChanged: (val) {
              final trimmed = val.trim();
              setState(() => _searchQuery = trimmed);
              if (_searchSourceIndex == 1) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 400), () {
                  _performServerSearch(trimmed);
                });
              }
            },
            onSubmitted: (val) {
              final trimmed = val.trim();
              setState(() => _searchQuery = trimmed);
              if (_searchSourceIndex == 1) {
                _performServerSearch(trimmed);
              }
            },
            hintText: _searchSourceIndex == 0
                ? 'Поиск в моей библиотеке...'
                : 'Поиск по 4800+ трекам на сайте...',
            hintStyle: WidgetStateProperty.all(const TextStyle(color: AppTheme.textMuted, fontSize: 14)),
            textStyle: WidgetStateProperty.all(const TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
            leading: const Icon(Icons.search_rounded, color: AppTheme.accentLight),
            trailing: [
              if (_searchQuery.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear_rounded, color: AppTheme.textMuted),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                      _serverSearchResults = [];
                      _serverSearchTotal = 0;
                    });
                  },
                ),
            ],
            backgroundColor: WidgetStateProperty.all(AppTheme.bg2),
            elevation: WidgetStateProperty.all(0),
            shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          ),
        ),

        // Переключатель источника поиска (Material You Chips)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Row(
            children: [
              _buildCategoryChip(
                label: 'Мои треки (${_allTracks.length})',
                isSelected: _searchSourceIndex == 0,
                onSelected: () => setState(() => _searchSourceIndex = 0),
              ),
              const SizedBox(width: 8),
              _buildCategoryChip(
                label: 'Треки на сайте (4800+)',
                isSelected: _searchSourceIndex == 1,
                onSelected: () {
                  setState(() => _searchSourceIndex = 1);
                  if (_searchQuery.isNotEmpty && _serverSearchResults.isEmpty) {
                    _performServerSearch(_searchQuery);
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        Expanded(
          child: _searchSourceIndex == 0
              ? _buildLocalSearchBody()
              : _buildServerSearchBody(),
        ),
      ],
    );
  }

  /// Локальный поиск по сохранённым трекам пользователя
  Widget _buildLocalSearchBody() {
    final myTracks = {..._allTracks, ..._likedTracks, ..._historyTracks}.toList();
    final results = _filterList(myTracks, _searchQuery);

    if (_searchQuery.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.library_music_rounded, size: 60, color: AppTheme.bg4),
            SizedBox(height: 12),
            Text(
              'Введите название трека или артиста',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (results.isEmpty) {
      return Center(
        child: Text('В вашей библиотеке ничего не найдено по запросу «$_searchQuery»',
            style: const TextStyle(color: AppTheme.textMuted)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Text('Найдено треков: ${results.length}',
              style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
        ),
        Expanded(
          child: ValueListenableBuilder<Track?>(
            valueListenable: widget.audioHandler.currentTrackNotifier,
            builder: (context, current, _) {
              return ListView.builder(
                itemExtent: 66.0,
                itemCount: results.length,
                itemBuilder: (context, i) {
                  final track = results[i];
                  return TrackTile(
                    track: track,
                    isPlaying: current?.id == track.id,
                    onTap: () => widget.audioHandler.playTrackList(results, i),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// Серверный поиск по всем 4800+ трекам сайта AuxBass
  Widget _buildServerSearchBody() {
    // 1. Если поисковый запрос пустой: показываем кнопку Шафла по сайту и популярные треки
    if (_searchQuery.isEmpty) {
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Карточка Шафл по всем трекам на сайте
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1B3120), Color(0xFF122216)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: AppTheme.accent.withAlpha(80)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withAlpha(40),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.casino_rounded, color: AppTheme.accentLight, size: 28),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Шафл по всем трекам на сайте',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Случайный микс из всей базы (4800+ треков)',
                                style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _startGlobalShuffle,
                          icon: const Icon(Icons.shuffle_rounded, size: 18),
                          label: const Text('Включить'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            foregroundColor: AppTheme.accentText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('🔥 Каталог треков AuxBass',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                ],
              ),
            ),
          ),
          SliverFixedExtentList(
            itemExtent: 66.0,
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final track = _globalTracks[i];
                return ValueListenableBuilder<Track?>(
                  valueListenable: widget.audioHandler.currentTrackNotifier,
                  builder: (context, current, _) {
                    return TrackTile(
                      track: track,
                      isPlaying: current?.id == track.id,
                      onTap: () {
                        widget.audioHandler.playTrackList(_globalTracks, i);
                      },
                    );
                  },
                );
              },
              childCount: _globalTracks.length,
            ),
          ),
        ],
      );
    }

    // 2. Идет поиск на сервере
    if (_isSearchingServer) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppTheme.accent)),
            SizedBox(height: 16),
            Text('Ищем среди 4800+ треков на сервере...', style: TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      );
    }

    // 3. Ничего не найдено
    if (_serverSearchResults.isEmpty) {
      return Center(
        child: Text(
          'По запросу «$_searchQuery» на сайте ничего не найдено',
          style: const TextStyle(color: AppTheme.textMuted),
        ),
      );
    }

    // 4. Результаты найдены
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Найдено треков: $_serverSearchTotal',
                  style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
              TextButton.icon(
                onPressed: () {
                  final list = List<Track>.from(_serverSearchResults)..shuffle();
                  widget.audioHandler.playTrackList(list, 0);
                },
                icon: const Icon(Icons.shuffle_rounded, size: 16, color: AppTheme.accentLight),
                label: const Text('Микс', style: TextStyle(color: AppTheme.accentLight, fontSize: 12)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ValueListenableBuilder<Track?>(
            valueListenable: widget.audioHandler.currentTrackNotifier,
            builder: (context, current, _) {
              return ListView.builder(
                itemExtent: 66.0,
                itemCount: _serverSearchResults.length,
                itemBuilder: (context, i) {
                  final track = _serverSearchResults[i];
                  return TrackTile(
                    track: track,
                    isPlaying: current?.id == track.id,
                    onTap: () => widget.audioHandler.playTrackList(_serverSearchResults, i),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ================= 3. БИБЛИОТЕКА (ТРЕКИ + ПЛЕЙЛИСТЫ + ИСТОРИЯ) =================
  Widget _buildLibraryTab() {
    return Column(
      children: [
        // Подкатегории: Все треки, Плейлисты, История (БЕЗ белой полоски!)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildCategoryChip(
                  label: _totalLibraryTracks > _allTracks.length
                      ? 'Все треки (${_allTracks.length}/$_totalLibraryTracks...)'
                      : 'Все треки (${_allTracks.length})',
                  isSelected: _libraryFilterIndex == 0,
                  onSelected: () => setState(() => _libraryFilterIndex = 0),
                ),
                const SizedBox(width: 8),
                _buildCategoryChip(
                  label: 'Плейлисты (${_playlists.length})',
                  isSelected: _libraryFilterIndex == 1,
                  onSelected: () => setState(() => _libraryFilterIndex = 1),
                ),
                const SizedBox(width: 8),
                _buildCategoryChip(
                  label: 'История (${_historyTracks.length})',
                  isSelected: _libraryFilterIndex == 2,
                  onSelected: () => setState(() => _libraryFilterIndex = 2),
                ),
              ],
            ),
          ),
        ),

        // Контент подкатегории
        Expanded(
          child: _libraryFilterIndex == 0
              ? _buildLibraryTracksList(_allTracks, 'В библиотеке пока нет треков')
              : _libraryFilterIndex == 1
                  ? _buildPlaylistsView()
                  : _buildLibraryTracksList(_historyTracks, 'История прослушиваний пуста'),
        ),
      ],
    );
  }

  Widget _buildLibraryTracksList(List<Track> list, String emptyText) {
    if (list.isEmpty) {
      return Center(child: Text(emptyText, style: const TextStyle(color: AppTheme.textMuted)));
    }
    return ValueListenableBuilder<Track?>(
      valueListenable: widget.audioHandler.currentTrackNotifier,
      builder: (context, current, _) {
        return ListView.builder(
          itemExtent: 66.0,
          itemCount: list.length,
          itemBuilder: (context, i) {
            final track = list[i];
            return TrackTile(
              track: track,
              isPlaying: current?.id == track.id,
              onTap: () => widget.audioHandler.playTrackList(list, i),
            );
          },
        );
      },
    );
  }

  // Вид плейлистов
  Widget _buildPlaylistsView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Ваши плейлисты (${_playlists.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
              TextButton.icon(
                onPressed: _showCreatePlaylistDialog,
                icon: const Icon(Icons.add_rounded, size: 20, color: AppTheme.accentLight),
                label: const Text('Создать', style: TextStyle(color: AppTheme.accentLight, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        Expanded(
          child: _playlists.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.queue_music_rounded, size: 64, color: AppTheme.bg4),
                      const SizedBox(height: 12),
                      const Text('У вас пока нет плейлистов', style: TextStyle(color: AppTheme.textSecondary)),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        onPressed: _showCreatePlaylistDialog,
                        child: const Text('Создать первый плейлист'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _playlists.length,
                  itemBuilder: (context, i) {
                    final pl = _playlists[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 52,
                            height: 52,
                            color: AppTheme.bg3,
                            child: pl.fullCoverUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: pl.fullCoverUrl!,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => const Icon(Icons.queue_music_rounded, color: AppTheme.accentLight),
                                  )
                                : const Icon(Icons.queue_music_rounded, color: AppTheme.accentLight),
                          ),
                        ),
                        title: Text(pl.name, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                        subtitle: Text('${pl.trackCount} треков', style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                        trailing: const Icon(Icons.play_circle_fill_rounded, color: AppTheme.accent, size: 36),
                        onTap: () => _openPlaylistTracks(pl),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showCreatePlaylistDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bg1,
        title: const Text('Новый плейлист'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Название плейлиста'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              try {
                final created = await _apiService.createPlaylist(name);
                setState(() => _playlists.insert(0, created));
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
                }
              }
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }

  void _openPlaylistTracks(Playlist playlist) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bg1,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (ctx, scrollController) {
            return FutureBuilder<List<Track>>(
              future: _apiService.getPlaylistTracks(playlist.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppTheme.accent)));
                }
                final tracks = snapshot.data ?? [];
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(playlist.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                                Text('${tracks.length} треков', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                              ],
                            ),
                          ),
                          if (tracks.isNotEmpty)
                            FilledButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                widget.audioHandler.playTrackList(tracks, 0);
                              },
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('Играть'),
                              style: FilledButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: AppTheme.accentText),
                            ),
                        ],
                      ),
                    ),
                    const Divider(color: AppTheme.bg4),
                    Expanded(
                      child: tracks.isEmpty
                          ? const Center(child: Text('В плейлисте нет треков', style: TextStyle(color: AppTheme.textMuted)))
                          : ListView.builder(
                              itemExtent: 66.0,
                              controller: scrollController,
                              itemCount: tracks.length,
                              itemBuilder: (context, i) {
                                final track = tracks[i];
                                return TrackTile(
                                  track: track,
                                  isPlaying: widget.audioHandler.currentTrack?.id == track.id,
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    widget.audioHandler.playTrackList(tracks, i);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  // ================= 4. ЛЮБИМЫЕ ТРЕКИ =================
  Widget _buildFavoritesTab() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E3A24), Color(0xFF132217)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTheme.accent.withAlpha(50)),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.accent,
                  boxShadow: [BoxShadow(color: AppTheme.accentGlow, blurRadius: 16)],
                ),
                child: const Icon(Icons.favorite_rounded, color: AppTheme.accentText, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Любимые треки', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                    const SizedBox(height: 4),
                    Text('${_likedTracks.length} треков в коллекции', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              if (_likedTracks.isNotEmpty)
                IconButton.filled(
                  onPressed: () {
                    final list = List<Track>.from(_likedTracks)..shuffle();
                    widget.audioHandler.playTrackList(list, 0);
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 28),
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: AppTheme.accentText,
                  ),
                ),
            ],
          ),
        ),

        Expanded(
          child: _likedTracks.isEmpty
              ? const Center(child: Text('Вы пока не добавили треки в любимые', style: TextStyle(color: AppTheme.textMuted)))
              : ValueListenableBuilder<Track?>(
                  valueListenable: widget.audioHandler.currentTrackNotifier,
                  builder: (context, current, _) {
                    return ListView.builder(
                      itemExtent: 66.0,
                      itemCount: _likedTracks.length,
                      itemBuilder: (context, i) {
                        final track = _likedTracks[i];
                        return TrackTile(
                          track: track,
                          isPlaying: current?.id == track.id,
                          onTap: () => widget.audioHandler.playTrackList(_likedTracks, i),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ================= 5. ПОДПИСКИ & ПОЛЬЗОВАТЕЛИ КАК НА САЙТЕ =================
  Widget _buildSubscriptionsTab() {
    return Column(
      children: [
        // Переключатель: Пользователи сайта / Telegram-каналы
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              _buildCategoryChip(
                label: 'Пользователи (${_globalUsers.length})',
                isSelected: _subscriptionsFilterIndex == 0,
                onSelected: () => setState(() => _subscriptionsFilterIndex = 0),
              ),
              const SizedBox(width: 8),
              _buildCategoryChip(
                label: 'Telegram-каналы',
                isSelected: _subscriptionsFilterIndex == 1,
                onSelected: () => setState(() => _subscriptionsFilterIndex = 1),
              ),
            ],
          ),
        ),

        Expanded(
          child: _subscriptionsFilterIndex == 0
              ? _buildUsersListView()
              : _buildTelegramChannelsView(),
        ),
      ],
    );
  }

  // Список пользователей AuxBass с сайта
  Widget _buildUsersListView() {
    if (_globalUsers.isEmpty) {
      return const Center(child: Text('Список пользователей пуст', style: TextStyle(color: AppTheme.textMuted)));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _globalUsers.length,
      itemBuilder: (context, i) {
        final u = _globalUsers[i];
        final isMe = u.id == widget.user.id;

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: _buildUserAvatar(
              avatarUrl: u.fullAvatarUrl,
              displayName: u.displayName,
              radius: 24,
              fontSize: 18,
              backgroundColor: isMe ? AppTheme.accent : AppTheme.bg3,
              textColor: isMe ? AppTheme.accentText : AppTheme.accentLight,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    u.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                ),
                if (isMe)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: AppTheme.accent, borderRadius: BorderRadius.circular(10)),
                    child: const Text('ВЫ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accentText)),
                  ),
              ],
            ),
            subtitle: Text(
              u.username != null ? '@${u.username}' : 'ID #${u.id}',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.bg3,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.bg4),
              ),
              child: Text(
                '${u.uploadCount} треков',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.accentLight),
              ),
            ),
            onTap: () => _openUserTracks(u),
          ),
        );
      },
    );
  }

  void _openUserTracks(GlobalUser targetUser) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bg1,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (ctx, scrollController) {
            return FutureBuilder<List<Track>>(
              future: _apiService.getUserTracks(targetUser.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppTheme.accent)));
                }
                final tracks = snapshot.data ?? [];
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                      child: Row(
                        children: [
                          _buildUserAvatar(
                            avatarUrl: targetUser.fullAvatarUrl,
                            displayName: targetUser.displayName,
                            radius: 24,
                            fontSize: 18,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(targetUser.displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                                Text('${tracks.length} треков', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                              ],
                            ),
                          ),
                          if (tracks.isNotEmpty)
                            FilledButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                widget.audioHandler.playTrackList(tracks, 0);
                              },
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('Слушать'),
                              style: FilledButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: AppTheme.accentText),
                            ),
                        ],
                      ),
                    ),
                    const Divider(color: AppTheme.bg4),
                    Expanded(
                      child: tracks.isEmpty
                          ? const Center(child: Text('У пользователя пока нет доступных треков', style: TextStyle(color: AppTheme.textMuted)))
                          : ListView.builder(
                              itemExtent: 66.0,
                              controller: scrollController,
                              itemCount: tracks.length,
                              itemBuilder: (context, i) {
                                final track = tracks[i];
                                return TrackTile(
                                  track: track,
                                  isPlaying: widget.audioHandler.currentTrack?.id == track.id,
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    widget.audioHandler.playTrackList(tracks, i);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildTelegramChannelsView() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: AppTheme.bg2,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTheme.bg4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.podcasts_rounded, color: AppTheme.accentLight, size: 28),
                  SizedBox(width: 12),
                  Text('Telegram-каналы', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Подключите каналы или группы в боте @auxbassbot, чтобы музыка из них автоматически сохранялась в вашу библиотеку AuxBass.',
                style: TextStyle(fontSize: 13.5, color: AppTheme.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () async {
                  final uri = Uri.parse('tg://resolve?domain=auxbassbot');
                  if (!await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication)) {
                    await launchUrl(Uri.parse('https://t.me/auxbassbot'), mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.add_link_rounded, size: 20),
                label: const Text('Подключить канал в Telegram'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: AppTheme.accentText,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        const Text('Статус синхронизации', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
        const SizedBox(height: 12),

        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.accent.withAlpha(35),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: AppTheme.accentLight, size: 20),
          ),
          title: const Text('Личные чаты & Сохранённое', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          subtitle: const Text('Музыка синхронизируется через @auxbassbot', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          tileColor: AppTheme.bg2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ],
    );
  }

  Widget _buildCategoryChip({required String label, required bool isSelected, required VoidCallback onSelected}) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected ? AppTheme.accentText : AppTheme.textSecondary,
      ),
      backgroundColor: AppTheme.bg2,
      selectedColor: AppTheme.accent,
      showCheckmark: false,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      side: BorderSide(color: isSelected ? AppTheme.accent : AppTheme.bg4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }
}

/// Виджет-обертка для предотвращения уничтожения вкладок при свайпах в PageView
class KeepAlivePage extends StatefulWidget {
  final Widget child;
  const KeepAlivePage({super.key, required this.child});

  @override
  State<KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<KeepAlivePage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
