import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../models/feed_drop.dart';
import '../models/global_user.dart';
import '../models/music_tag.dart';
import '../models/paged_tracks.dart';
import '../models/playlist.dart';
import '../models/social_user.dart';
import '../models/track.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/audio_player_handler.dart';
import '../services/auth_service.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/track_tile.dart';
import 'album_detail_screen.dart';
import 'artist_detail_screen.dart';
import 'login_screen.dart';
import 'playlist_detail_screen.dart';
import 'settings_screen.dart';
import 'user_profile_screen.dart';

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
  int _globalTracksTotal = 0;
  int _globalTracksPage = 1;
  bool _isLoadingMoreGlobal = false;
  bool _hasMoreGlobal = true;
  final ScrollController _globalScrollController = ScrollController();
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
  int _serverSearchPage = 1;
  bool _isLoadingMoreServerSearch = false;
  bool _hasMoreServerSearch = false;
  final ScrollController _serverSearchScrollController = ScrollController();
  String _lastServerQuery = '';
  Timer? _searchDebounce;

  // Контроллер для свайпов между 5 вкладками
  late final PageController _pageController;

  // Библиотека: фильтр подкатегорий (0 - Все треки, 1 - Плейлисты, 2 - Альбомы, 3 - Артисты, 4 - История)
  int _libraryFilterIndex = 0;

  // --- 1. Кенты (Социалка и подписки) ---
  List<FeedDrop> _feedDrops = [];
  List<SocialUser> _followingList = [];
  List<SocialUser> _followersList = [];
  List<SocialUser> _socialSearchResults = [];
  bool _isSocialLoading = false;
  int _kentySubTab = 0; // 0 - Лента, 1 - Подписки, 2 - Подписчики, 3 - Поиск
  final TextEditingController _kentySearchController = TextEditingController();
  String _kentySearchQuery = '';
  Timer? _kentySearchDebounce;

  // --- 2. Альбомы и Артисты ---
  List<Album> _libraryAlbums = [];
  List<Album> _globalAlbums = [];
  int _albumsScopeIndex = 0; // 0 - В медиатеке, 1 - Все на сайте
  bool _isLoadingAlbums = false;

  List<Artist> _libraryArtists = [];
  List<Artist> _globalArtists = [];
  int _artistsScopeIndex = 0; // 0 - В медиатеке, 1 - Все на сайте
  bool _isLoadingArtists = false;

  // --- 7. Жанры, теги и рекомендации ---
  List<MusicTag> _searchTags = [];
  List<String> _recentSearches = [];
  List<Track> _popularTracks = [];
  List<Track> _recentTracks = [];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentNavIndex);
    _globalScrollController.addListener(_onGlobalScroll);
    _serverSearchScrollController.addListener(_onServerSearchScroll);
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
    _kentySearchDebounce?.cancel();
    _globalScrollController.dispose();
    _serverSearchScrollController.dispose();
    _pageController.dispose();
    _searchController.dispose();
    _kentySearchController.dispose();
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
        _apiService.getGlobalTracksPage(page: 1, perPage: 100),
        _apiService.getPlaylists(),
        _apiService.getGlobalUsers(),
      ]);

      final firstLib = results[0] as PagedTracks;
      final firstGlobal = results[2] as PagedTracks;

      if (mounted) {
        setState(() {
          _allTracks = List.from(firstLib.items);
          _totalLibraryTracks = firstLib.total;
          _historyTracks = results[1] as List<Track>;
          _globalTracks = List.from(firstGlobal.items);
          _globalTracksTotal = firstGlobal.total;
          _globalTracksPage = 1;
          _hasMoreGlobal = firstGlobal.hasMore;
          _playlists = results[3] as List<Playlist>;
          _globalUsers = results[4] as List<GlobalUser>;
          _isLoading = false;
        });
      }

      // 2. В фоне выкачиваем все остальные страницы библиотеки (до 1000+ треков) и лайков
      _loadAllRemainingPages();

      // 3. Загружаем социалку («Кенты»), теги и рекомендации
      _loadSocialData();
      _loadTagsAndRecommendations();
      _loadRecentSearches();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  // --- Социальные данные («Кенты») ---
  Future<void> _loadSocialData() async {
    setState(() => _isSocialLoading = true);
    try {
      final feedFuture = _apiService.getSocialFeed();
      final followingFuture = _apiService.getFollowing();
      final followersFuture = _apiService.getFollowers();

      final res = await Future.wait([
        feedFuture.catchError((_) => <FeedDrop>[]),
        followingFuture.catchError((_) => <SocialUser>[]),
        followersFuture.catchError((_) => <SocialUser>[]),
      ]);

      if (mounted) {
        setState(() {
          _feedDrops = res[0] as List<FeedDrop>;
          _followingList = res[1] as List<SocialUser>;
          _followersList = res[2] as List<SocialUser>;
          _isSocialLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isSocialLoading = false);
    }
  }

  void _searchKenty(String query) {
    _kentySearchDebounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _kentySearchQuery = '';
        _socialSearchResults = [];
      });
      return;
    }

    _kentySearchDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final users = await _apiService.searchSocialUsers(query);
        if (mounted && _kentySearchQuery == query.trim()) {
          setState(() {
            _socialSearchResults = users;
          });
        }
      } catch (_) {}
    });
  }

  // --- Альбомы и Артисты ---
  Future<void> _loadAlbums() async {
    setState(() => _isLoadingAlbums = true);
    try {
      final libAlb = await _apiService.getAlbums(scope: 'library');
      final globAlb = await _apiService.getAlbums(scope: 'global');
      if (mounted) {
        setState(() {
          _libraryAlbums = libAlb;
          _globalAlbums = globAlb;
          _isLoadingAlbums = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingAlbums = false);
    }
  }

  Future<void> _loadArtists() async {
    setState(() => _isLoadingArtists = true);
    try {
      final libArt = await _apiService.getArtists(scope: 'library');
      final globArt = await _apiService.getArtists(scope: 'global');
      if (mounted) {
        setState(() {
          _libraryArtists = libArt;
          _globalArtists = globArt;
          _isLoadingArtists = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingArtists = false);
    }
  }

  // --- Теги, история поиска и рекомендации ---
  Future<void> _loadTagsAndRecommendations() async {
    try {
      final tagsFuture = _apiService.getTags();
      final popFuture = _apiService.getGlobalPopular(limit: 15);
      final recFuture = _apiService.getGlobalRecent(limit: 15);

      final res = await Future.wait([
        tagsFuture.catchError((_) => <MusicTag>[]),
        popFuture.catchError((_) => <Track>[]),
        recFuture.catchError((_) => <Track>[]),
      ]);

      if (mounted) {
        setState(() {
          _searchTags = res[0] as List<MusicTag>;
          _popularTracks = res[1] as List<Track>;
          _recentTracks = res[2] as List<Track>;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('auxbass_recent_searches') ?? [];
      if (mounted) {
        setState(() => _recentSearches = list);
      }
    } catch (_) {}
  }

  Future<void> _saveRecentSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = List<String>.from(_recentSearches);
      list.remove(q);
      list.insert(0, q);
      if (list.length > 15) list.removeLast();
      await prefs.setStringList('auxbass_recent_searches', list);
      if (mounted) setState(() => _recentSearches = list);
    } catch (_) {}
  }

  Future<void> _removeRecentSearch(String query) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = List<String>.from(_recentSearches)..remove(query);
      await prefs.setStringList('auxbass_recent_searches', list);
      if (mounted) setState(() => _recentSearches = list);
    } catch (_) {}
  }

  Future<void> _clearRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auxbass_recent_searches');
      if (mounted) setState(() => _recentSearches = []);
    } catch (_) {}
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

  void _onGlobalScroll() {
    if (_globalScrollController.hasClients &&
        _globalScrollController.position.pixels >=
            _globalScrollController.position.maxScrollExtent - 400) {
      _loadMoreGlobalTracks();
    }
  }

  Future<void> _loadMoreGlobalTracks() async {
    if (_isLoadingMoreGlobal || !_hasMoreGlobal) return;
    setState(() => _isLoadingMoreGlobal = true);
    try {
      final nextPage = _globalTracksPage + 1;
      final paged = await _apiService.getGlobalTracksPage(page: nextPage, perPage: 100);
      if (mounted) {
        setState(() {
          _globalTracksPage = nextPage;
          _globalTracksTotal = paged.total;
          _hasMoreGlobal = paged.hasMore;
          final existingIds = _globalTracks.map((t) => t.id).toSet();
          final newItems = paged.items.where((t) => !existingIds.contains(t.id)).toList();
          _globalTracks.addAll(newItems);
        });
      }
    } catch (e) {
      debugPrint('[HomeScreen] Ошибка загрузки следующей страницы каталога: $e');
    } finally {
      if (mounted) setState(() => _isLoadingMoreGlobal = false);
    }
  }

  void _onServerSearchScroll() {
    if (_serverSearchScrollController.hasClients &&
        _serverSearchScrollController.position.pixels >=
            _serverSearchScrollController.position.maxScrollExtent - 400) {
      _loadMoreServerSearch();
    }
  }

  Future<void> _loadMoreServerSearch() async {
    if (_isLoadingMoreServerSearch || !_hasMoreServerSearch || _searchQuery.isEmpty) return;
    setState(() => _isLoadingMoreServerSearch = true);
    try {
      final nextPage = _serverSearchPage + 1;
      final paged = await _apiService.searchGlobalTracks(_searchQuery, page: nextPage, perPage: 100);
      if (mounted && _lastServerQuery == _searchQuery) {
        setState(() {
          _serverSearchPage = nextPage;
          _serverSearchTotal = paged.total;
          _hasMoreServerSearch = paged.hasMore;
          final existingIds = _serverSearchResults.map((t) => t.id).toSet();
          final newItems = paged.items.where((t) => !existingIds.contains(t.id)).toList();
          _serverSearchResults.addAll(newItems);
        });
      }
    } catch (e) {
      debugPrint('[HomeScreen] Ошибка загрузки следующей страницы поиска: $e');
    } finally {
      if (mounted) setState(() => _isLoadingMoreServerSearch = false);
    }
  }

  /// Поиск по всем 4800+ трекам на сервере
  Future<void> _performServerSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _serverSearchResults = [];
        _serverSearchTotal = 0;
        _serverSearchPage = 1;
        _hasMoreServerSearch = false;
        _isSearchingServer = false;
      });
      return;
    }
    _lastServerQuery = query;

    setState(() {
      _isSearchingServer = true;
      _serverSearchPage = 1;
    });

    try {
      final paged = await _apiService.searchGlobalTracks(query, page: 1, perPage: 100);
      if (mounted && _lastServerQuery == query) {
        _saveRecentSearch(query);
        setState(() {
          _serverSearchResults = paged.items;
          _serverSearchTotal = paged.total;
          _serverSearchPage = 1;
          _hasMoreServerSearch = paged.hasMore;
          _isSearchingServer = false;
        });
      }
    } catch (_) {
      if (mounted && _lastServerQuery == query) {
        setState(() {
          _serverSearchResults = [];
          _serverSearchTotal = 0;
          _hasMoreServerSearch = false;
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
    final cleanName = displayName.replaceFirst(RegExp(r'^@+'), '').trim();
    final initial = cleanName.isNotEmpty ? cleanName.characters.first.toUpperCase() : 'U';
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

                const SizedBox(height: 16),

                // Мой профиль
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withAlpha(35),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.person_rounded, color: AppTheme.accentLight, size: 22),
                  ),
                  title: const Text('Мой профиль', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  subtitle: const Text('Медиатека, треки и кенты', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openUserProfile(user.id);
                  },
                ),
                const SizedBox(height: 8),

                // Настройки
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withAlpha(35),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.settings_rounded, color: AppTheme.accentLight, size: 22),
                  ),
                  title: const Text('Настройки', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  subtitle: const Text('Кэш, SoundCloud, фоновое воспроизведение и обновления', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SettingsScreen(
                          user: widget.user,
                          audioHandler: widget.audioHandler,
                          onRefreshRequired: _loadAllData,
                        ),
                      ),
                    );
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
          PopupMenuButton<String>(
            offset: const Offset(0, 48),
            color: AppTheme.bg2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (val) {
              if (val == 'profile') {
                _openUserProfile(widget.user.id);
              } else if (val == 'settings') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(
                      user: widget.user,
                      audioHandler: widget.audioHandler,
                      onRefreshRequired: _loadAllData,
                    ),
                  ),
                );
              } else if (val == 'modal') {
                _showProfileModal();
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    const Icon(Icons.person_rounded, color: AppTheme.accentLight, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.user.displayName,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings_rounded, color: AppTheme.accentLight, size: 20),
                    SizedBox(width: 12),
                    Text('Настройки', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'modal',
                child: Row(
                  children: [
                    Icon(Icons.account_circle_outlined, color: AppTheme.textSecondary, size: 20),
                    SizedBox(width: 12),
                    Text('Сводка профиля', style: TextStyle(color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            ],
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
                          KeepAlivePage(child: _buildKentyTab()),
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
              icon: Icon(Icons.people_outline_rounded),
              selectedIcon: Icon(Icons.people_rounded),
              label: 'Кенты',
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
        return 'Кенты';
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
                        'всем привет я ауе',
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
                    audioHandler: widget.audioHandler,
                    onTap: () {
                      widget.audioHandler.playTrackList(_globalTracks, _globalTracks.indexOf(track));
                    },
                  );
                },
              );
            }),

          const SizedBox(height: 24),

          if (_historyTracks.isNotEmpty) ...[
            const Text('Недавно слушали', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            ..._historyTracks.take(5).map((track) {
              return ValueListenableBuilder<Track?>(
                valueListenable: widget.audioHandler.currentTrackNotifier,
                builder: (context, current, _) {
                  return TrackTile(
                    track: track,
                    isPlaying: current?.id == track.id,
                    audioHandler: widget.audioHandler,
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
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
                : 'Поиск по ${_globalTracksTotal > 0 ? _globalTracksTotal : 4800}+ трекам на сайте...',
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
                      _serverSearchPage = 1;
                      _hasMoreServerSearch = false;
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
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
          child: Row(
            children: [
              _buildCategoryChip(
                label: 'Мои треки (${_allTracks.length})',
                isSelected: _searchSourceIndex == 0,
                onSelected: () => setState(() => _searchSourceIndex = 0),
              ),
              const SizedBox(width: 8),
              _buildCategoryChip(
                label: 'Треки на сайте (${_globalTracksTotal > 0 ? _globalTracksTotal : "4800+"})',
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

        // Популярные теги и стили (#phonk, #lo-fi, #dnb и т.д.)
        if (_searchTags.isNotEmpty)
          Container(
            height: 40,
            margin: const EdgeInsets.only(top: 6, bottom: 2),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _searchTags.length,
              itemBuilder: (context, idx) {
                final tag = _searchTags[idx];
                final isSelected = _searchQuery.toLowerCase() == tag.name.toLowerCase() ||
                    _searchQuery.toLowerCase() == '#${tag.name.toLowerCase()}';
                return Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: ActionChip(
                    label: Text('#${tag.name}'),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? AppTheme.accentText : AppTheme.textPrimary,
                    ),
                    backgroundColor: isSelected ? AppTheme.accent : AppTheme.bg2,
                    side: BorderSide(color: isSelected ? AppTheme.accent : AppTheme.bg4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onPressed: () {
                      _searchController.text = tag.name;
                      setState(() {
                        _searchQuery = tag.name;
                        _searchSourceIndex = 1; // Автоматически переключаем на поиск по сайту
                      });
                      _performServerSearch(tag.name);
                    },
                  ),
                );
              },
            ),
          ),

        // История недавних поисковых запросов
        if (_searchQuery.isEmpty && _recentSearches.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.history_rounded, size: 16, color: AppTheme.textMuted),
                const SizedBox(width: 6),
                const Text('Недавно искали:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _recentSearches.take(6).map((term) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InputChip(
                            label: Text(term, style: const TextStyle(fontSize: 11, color: AppTheme.textPrimary)),
                            backgroundColor: AppTheme.bg2,
                            side: const BorderSide(color: AppTheme.bg4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            onPressed: () {
                              _searchController.text = term;
                              setState(() {
                                _searchQuery = term;
                                _searchSourceIndex = 1;
                              });
                              _performServerSearch(term);
                            },
                            onDeleted: () => _removeRecentSearch(term),
                            deleteIconColor: AppTheme.textMuted,
                            deleteIcon: const Icon(Icons.close_rounded, size: 14),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _clearRecentSearches,
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('Очистить', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                ),
              ],
            ),
          ),

        const SizedBox(height: 4),

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
                    audioHandler: widget.audioHandler,
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
    // 1. Если поисковый запрос пустой: показываем кнопку Шафла по сайту, популярное, новинки и каталог
    if (_searchQuery.isEmpty) {
      return CustomScrollView(
        controller: _globalScrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
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

                  // Секция 1: Популярно на AuxBass
                  if (_popularTracks.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Row(
                      children: [
                        Icon(Icons.local_fire_department_rounded, color: Colors.orangeAccent, size: 20),
                        SizedBox(width: 6),
                        Text('Популярно на AuxBass', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 184,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _popularTracks.length,
                        itemBuilder: (context, idx) {
                          final tr = _popularTracks[idx];
                          return _buildTrackCard(tr, _popularTracks, idx);
                        },
                      ),
                    ),
                  ],

                  // Секция 2: Свежие новинки каталога
                  if (_recentTracks.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const Row(
                      children: [
                        Icon(Icons.auto_awesome_rounded, color: AppTheme.accentLight, size: 19),
                        SizedBox(width: 6),
                        Text('Свежие новинки каталога', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 184,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _recentTracks.length,
                        itemBuilder: (context, idx) {
                          final tr = _recentTracks[idx];
                          return _buildTrackCard(tr, _recentTracks, idx);
                        },
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Text('🔥 Каталог треков AuxBass',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      const SizedBox(width: 8),
                      Text(
                        '(${_globalTracks.length}${_globalTracksTotal > 0 ? " из $_globalTracksTotal" : ""})',
                        style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
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
                      audioHandler: widget.audioHandler,
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
          if (_isLoadingMoreGlobal)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24.0),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(AppTheme.accent)),
                  ),
                ),
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
              Text('Найдено треков: $_serverSearchTotal (${_serverSearchResults.length} загружено)',
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
                controller: _serverSearchScrollController,
                itemExtent: 66.0,
                itemCount: _serverSearchResults.length + (_isLoadingMoreServerSearch ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i == _serverSearchResults.length) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(AppTheme.accent)),
                        ),
                      ),
                    );
                  }
                  final track = _serverSearchResults[i];
                  return TrackTile(
                    track: track,
                    isPlaying: current?.id == track.id,
                    audioHandler: widget.audioHandler,
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

  Widget _buildTrackCard(Track tr, List<Track> queue, int index) {
    return GestureDetector(
      onTap: () => widget.audioHandler.playTrackList(queue, index),
      child: Container(
        width: 124,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: AppTheme.bg2,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: SizedBox(
                    width: 124,
                    height: 112,
                    child: tr.fullCoverUrl != null
                        ? CachedNetworkImage(
                            imageUrl: tr.fullCoverUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(color: AppTheme.bg3),
                            errorWidget: (_, __, ___) => Container(
                              color: AppTheme.bg3,
                              child: const Icon(Icons.music_note_rounded, color: AppTheme.textMuted),
                            ),
                          )
                        : Container(
                            color: AppTheme.bg3,
                            child: const Icon(Icons.music_note_rounded, color: AppTheme.textMuted),
                          ),
                  ),
                ),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: AppTheme.accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(7.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tr.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                  ),
                  if (tr.playCount > 0) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.headphones_rounded, size: 10, color: AppTheme.textMuted),
                        const SizedBox(width: 3),
                        Text(
                          tr.formattedPlayCount,
                          style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= 3. БИБЛИОТЕКА (ТРЕКИ + ПЛЕЙЛИСТЫ + АЛЬБОМЫ + АРТИСТЫ + ИСТОРИЯ) =================
  Widget _buildLibraryTab() {
    return Column(
      children: [
        // Подкатегории: Все треки, Плейлисты, Альбомы, Артисты, История
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
                  label: 'Альбомы (${_albumsScopeIndex == 0 ? _libraryAlbums.length : _globalAlbums.length})',
                  isSelected: _libraryFilterIndex == 2,
                  onSelected: () {
                    setState(() => _libraryFilterIndex = 2);
                    if (_libraryAlbums.isEmpty && _globalAlbums.isEmpty) _loadAlbums();
                  },
                ),
                const SizedBox(width: 8),
                _buildCategoryChip(
                  label: 'Артисты (${_artistsScopeIndex == 0 ? _libraryArtists.length : _globalArtists.length})',
                  isSelected: _libraryFilterIndex == 3,
                  onSelected: () {
                    setState(() => _libraryFilterIndex = 3);
                    if (_libraryArtists.isEmpty && _globalArtists.isEmpty) _loadArtists();
                  },
                ),
                const SizedBox(width: 8),
                _buildCategoryChip(
                  label: 'История (${_historyTracks.length})',
                  isSelected: _libraryFilterIndex == 4,
                  onSelected: () => setState(() => _libraryFilterIndex = 4),
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
                  : _libraryFilterIndex == 2
                      ? _buildAlbumsView()
                      : _libraryFilterIndex == 3
                          ? _buildArtistsView()
                          : _buildLibraryTracksList(_historyTracks, 'История прослушиваний пуста'),
        ),
      ],
    );
  }

  /// Вкладка Альбомы (В медиатеке / На сайте)
  Widget _buildAlbumsView() {
    final albums = _albumsScopeIndex == 0 ? _libraryAlbums : _globalAlbums;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Row(
            children: [
              _buildCategoryChip(
                label: 'В медиатеке (${_libraryAlbums.length})',
                isSelected: _albumsScopeIndex == 0,
                onSelected: () {
                  setState(() => _albumsScopeIndex = 0);
                  if (_libraryAlbums.isEmpty) _loadAlbums();
                },
              ),
              const SizedBox(width: 8),
              _buildCategoryChip(
                label: 'Все на сайте (${_globalAlbums.length})',
                isSelected: _albumsScopeIndex == 1,
                onSelected: () {
                  setState(() => _albumsScopeIndex = 1);
                  if (_globalAlbums.isEmpty) _loadAlbums();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoadingAlbums && albums.isEmpty
              ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
              : albums.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.album_outlined, size: 54, color: AppTheme.textMuted),
                          const SizedBox(height: 12),
                          const Text('Альбомов пока нет', style: TextStyle(color: AppTheme.textMuted)),
                          const SizedBox(height: 12),
                          FilledButton.tonal(
                            onPressed: _loadAlbums,
                            child: const Text('Загрузить альбомы'),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: 0.78,
                      ),
                      itemCount: albums.length,
                      itemBuilder: (context, idx) {
                        final alb = albums[idx];
                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AlbumDetailScreen(
                                  albumId: alb.id,
                                  initialAlbum: alb,
                                  audioHandler: widget.audioHandler,
                                ),
                              ),
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppTheme.bg2,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: alb.coverUrl != null
                                          ? CachedNetworkImage(
                                              imageUrl: alb.coverUrl!,
                                              fit: BoxFit.cover,
                                              placeholder: (_, __) => Container(color: AppTheme.bg3),
                                              errorWidget: (_, __, ___) => Container(
                                                color: AppTheme.bg3,
                                                child: const Icon(Icons.album_rounded, color: AppTheme.textMuted, size: 40),
                                              ),
                                            )
                                          : Container(
                                              color: AppTheme.bg3,
                                              child: const Icon(Icons.album_rounded, color: AppTheme.textMuted, size: 40),
                                            ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(10.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        alb.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        alb.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                      ),
                                      if (alb.year != null && alb.year! > 0)
                                        Text(
                                          '${alb.year}',
                                          style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  /// Вкладка Артисты (В медиатеке / На сайте)
  Widget _buildArtistsView() {
    final artists = _artistsScopeIndex == 0 ? _libraryArtists : _globalArtists;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Row(
            children: [
              _buildCategoryChip(
                label: 'В медиатеке (${_libraryArtists.length})',
                isSelected: _artistsScopeIndex == 0,
                onSelected: () {
                  setState(() => _artistsScopeIndex = 0);
                  if (_libraryArtists.isEmpty) _loadArtists();
                },
              ),
              const SizedBox(width: 8),
              _buildCategoryChip(
                label: 'Все на сайте (${_globalArtists.length})',
                isSelected: _artistsScopeIndex == 1,
                onSelected: () {
                  setState(() => _artistsScopeIndex = 1);
                  if (_globalArtists.isEmpty) _loadArtists();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoadingArtists && artists.isEmpty
              ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
              : artists.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.person_outline_rounded, size: 54, color: AppTheme.textMuted),
                          const SizedBox(height: 12),
                          const Text('Артистов пока нет', style: TextStyle(color: AppTheme.textMuted)),
                          const SizedBox(height: 12),
                          FilledButton.tonal(
                            onPressed: _loadArtists,
                            child: const Text('Загрузить артистов'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      itemCount: artists.length,
                      itemBuilder: (context, idx) {
                        final art = artists[idx];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            leading: Container(
                              width: 48,
                              height: 48,
                              decoration: const BoxDecoration(shape: BoxShape.circle),
                              child: ClipOval(
                                child: art.imageUrl != null
                                    ? CachedNetworkImage(
                                        imageUrl: art.imageUrl!,
                                        fit: BoxFit.cover,
                                        placeholder: (_, __) => Container(color: AppTheme.bg3),
                                        errorWidget: (_, __, ___) => Container(
                                          color: AppTheme.bg3,
                                          child: const Icon(Icons.person_rounded, color: AppTheme.textMuted),
                                        ),
                                      )
                                    : Container(
                                        color: AppTheme.bg3,
                                        child: const Icon(Icons.person_rounded, color: AppTheme.textMuted),
                                      ),
                              ),
                            ),
                            title: Text(
                              art.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              [
                                if (art.trackCount > 0) '${art.trackCount} треков',
                                if (art.albumCount > 0) '${art.albumCount} альбомов',
                              ].join(' • '),
                              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ArtistDetailScreen(
                                    artistName: art.name,
                                    initialArtist: art,
                                    audioHandler: widget.audioHandler,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
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
              audioHandler: widget.audioHandler,
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
    final deleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PlaylistDetailScreen(
          playlist: playlist,
          audioHandler: widget.audioHandler,
          onPlaylistDeleted: () {
            setState(() {
              _playlists.removeWhere((p) => p.id == playlist.id);
            });
          },
        ),
      ),
    );
    if (deleted == true) {
      setState(() {
        _playlists.removeWhere((p) => p.id == playlist.id);
      });
    }
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
                          audioHandler: widget.audioHandler,
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

  // ================= 5. РАЗДЕЛ «КЕНТЫ» (СОЦИАЛКА, ЛЕНТА, ПОДПИСКИ) =================
  Widget _buildKentyTab() {
    return Column(
      children: [
        // Шапка профиля пользователя и счетчики социалки
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.bg2,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.bg4),
          ),
          child: Row(
            children: [
              _buildUserAvatar(
                avatarUrl: widget.user.fullAvatarUrl,
                displayName: widget.user.displayName,
                radius: 26,
                fontSize: 18,
                backgroundColor: AppTheme.accent,
                textColor: AppTheme.accentText,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
                    ),
                    if (widget.user.username != null)
                      Text(
                        '@${widget.user.username}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.accentLight),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          '${_followingList.length} подписок',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                        ),
                        const Text(' • ', style: TextStyle(color: AppTheme.textMuted)),
                        Text(
                          '${_followersList.length} подписчиков',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: _isSocialLoading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent))
                    : const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary),
                tooltip: 'Обновить ленту и кентов',
                onPressed: _loadSocialData,
              ),
            ],
          ),
        ),

        // Подкатегории Кентов: Лента, Подписки, Подписчики, Поиск, TG-Каналы
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildCategoryChip(
                  label: 'Лента (${_feedDrops.length})',
                  isSelected: _kentySubTab == 0,
                  onSelected: () => setState(() => _kentySubTab = 0),
                ),
                const SizedBox(width: 8),
                _buildCategoryChip(
                  label: 'Подписки (${_followingList.length})',
                  isSelected: _kentySubTab == 1,
                  onSelected: () => setState(() => _kentySubTab = 1),
                ),
                const SizedBox(width: 8),
                _buildCategoryChip(
                  label: 'Подписчики (${_followersList.length})',
                  isSelected: _kentySubTab == 2,
                  onSelected: () => setState(() => _kentySubTab = 2),
                ),
                const SizedBox(width: 8),
                _buildCategoryChip(
                  label: 'Поиск кентов',
                  isSelected: _kentySubTab == 3,
                  onSelected: () => setState(() => _kentySubTab = 3),
                ),
                const SizedBox(width: 8),
                _buildCategoryChip(
                  label: 'TG-Каналы',
                  isSelected: _kentySubTab == 4,
                  onSelected: () => setState(() => _kentySubTab = 4),
                ),
              ],
            ),
          ),
        ),

        Expanded(
          child: _kentySubTab == 0
              ? _buildFeedView()
              : _kentySubTab == 1
                  ? _buildFollowingView()
                  : _kentySubTab == 2
                      ? _buildFollowersView()
                      : _kentySubTab == 3
                          ? _buildSearchKentyView()
                          : _buildTelegramChannelsView(),
        ),
      ],
    );
  }

  /// 1. Лента активности от кентов
  Widget _buildFeedView() {
    if (_isSocialLoading && _feedDrops.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.accent));
    }

    if (_feedDrops.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.dynamic_feed_rounded, size: 56, color: AppTheme.textMuted),
              const SizedBox(height: 14),
              const Text(
                'Лента пока пуста',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 6),
              const Text(
                'Здесь будут появляться обновления треков от пользователей, на которых вы подписаны.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => setState(() => _kentySubTab = 3),
                child: const Text('Найти кентов'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _feedDrops.length,
      itemBuilder: (context, idx) {
        final drop = _feedDrops[idx];
        final uploader = drop.uploader;
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: AppTheme.bg2,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.bg4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Шапка дропа: Автор, действие, кнопка перехода в профиль
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (uploader != null) _openUserProfile(uploader.id, initialUser: uploader);
                      },
                      child: _buildUserAvatar(
                        avatarUrl: uploader?.fullAvatarUrl,
                        displayName: uploader?.displayName ?? 'Кент',
                        radius: 20,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (uploader != null) _openUserProfile(uploader.id, initialUser: uploader);
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              uploader?.displayName ?? 'Пользователь',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary),
                            ),
                            Text(
                              drop.action,
                              style: const TextStyle(fontSize: 12, color: AppTheme.accentLight),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (drop.tracks.isNotEmpty)
                      IconButton.filledTonal(
                        style: IconButton.styleFrom(
                          backgroundColor: AppTheme.accent.withAlpha(35),
                          padding: const EdgeInsets.all(8),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, color: AppTheme.accentLight, size: 20),
                        tooltip: 'Слушать все треки из дропа',
                        onPressed: () => widget.audioHandler.playTrackList(drop.tracks, 0),
                      ),
                  ],
                ),
              ),

              // Список треков дропа
              ...drop.tracks.map((track) {
                return ValueListenableBuilder<Track?>(
                  valueListenable: widget.audioHandler.currentTrackNotifier,
                  builder: (context, current, _) {
                    return TrackTile(
                      track: track,
                      isPlaying: current?.id == track.id,
                      audioHandler: widget.audioHandler,
                      onTap: () => widget.audioHandler.playTrackList(drop.tracks, drop.tracks.indexOf(track)),
                    );
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  /// 2. Список подписок
  Widget _buildFollowingView() {
    if (_followingList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_add_disabled_rounded, size: 54, color: AppTheme.textMuted),
            const SizedBox(height: 12),
            const Text('Вы пока ни на кого не подписаны', style: TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 14),
            FilledButton.tonal(
              onPressed: () => setState(() => _kentySubTab = 3),
              child: const Text('Найти кентов'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _followingList.length,
      itemBuilder: (context, idx) {
        final u = _followingList[idx];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: _buildUserAvatar(
              avatarUrl: u.fullAvatarUrl,
              displayName: u.displayName,
              radius: 22,
              fontSize: 16,
            ),
            title: Text(u.displayName, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            subtitle: Text(
              (u.username != null && u.username!.trim().isNotEmpty)
                  ? '@${u.username!.replaceFirst('@', '').trim()}'
                  : '${u.trackCount} треков',
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () async {
                    await _apiService.unfollowUser(u.id);
                    setState(() {
                      _followingList.removeAt(idx);
                    });
                  },
                  child: const Text('Отписаться', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                  onPressed: () => _openUserProfile(u.id, initialUser: u),
                ),
              ],
            ),
            onTap: () => _openUserProfile(u.id, initialUser: u),
          ),
        );
      },
    );
  }

  /// 3. Список подписчиков
  Widget _buildFollowersView() {
    if (_followersList.isEmpty) {
      return const Center(
        child: Text('У вас пока нет подписчиков', style: TextStyle(color: AppTheme.textMuted)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _followersList.length,
      itemBuilder: (context, idx) {
        final u = _followersList[idx];
        final isFollowingBack = _followingList.any((f) => f.id == u.id) || u.isFollowing;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: _buildUserAvatar(
              avatarUrl: u.fullAvatarUrl,
              displayName: u.displayName,
              radius: 22,
              fontSize: 16,
            ),
            title: Text(u.displayName, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            subtitle: Text(
              (u.username != null && u.username!.trim().isNotEmpty)
                  ? '@${u.username!.replaceFirst('@', '').trim()}'
                  : '${u.trackCount} треков',
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isFollowingBack)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.bg3,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('Взаимно', style: TextStyle(fontSize: 11, color: AppTheme.accentLight, fontWeight: FontWeight.bold)),
                  )
                else
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onPressed: () async {
                      final ok = await _apiService.followUser(u.id);
                      if (ok) {
                        setState(() {
                          u.isFollowing = true;
                          _followingList.add(u);
                        });
                      }
                    },
                    child: const Text('В ответ', style: TextStyle(fontSize: 11)),
                  ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                  onPressed: () => _openUserProfile(u.id, initialUser: u),
                ),
              ],
            ),
            onTap: () => _openUserProfile(u.id, initialUser: u),
          ),
        );
      },
    );
  }

  /// 4. Поиск кентов
  Widget _buildSearchKentyView() {
    final results = _kentySearchQuery.isNotEmpty ? _socialSearchResults : _globalUsers.map((g) => SocialUser(
      id: g.id,
      username: g.username,
      rawDisplayName: g.displayName,
      customNickname: g.displayName,
      photoUrl: g.avatarUrl,
      trackCount: g.uploadCount,
      isFollowing: _followingList.any((f) => f.id == g.id),
    )).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: TextField(
            controller: _kentySearchController,
            onChanged: (val) {
              setState(() => _kentySearchQuery = val);
              _searchKenty(val);
            },
            style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Поиск по никнейму или @username...',
              hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
              prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.accentLight, size: 20),
              suffixIcon: _kentySearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.textMuted),
                      onPressed: () {
                        _kentySearchController.clear();
                        setState(() {
                          _kentySearchQuery = '';
                          _socialSearchResults = [];
                        });
                      },
                    )
                  : null,
              filled: true,
              fillColor: AppTheme.bg2,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
        ),

        Expanded(
          child: results.isEmpty
              ? Center(
                  child: Text(
                    _kentySearchQuery.isNotEmpty ? 'Пользователь не найден' : 'Список пользователей пуст',
                    style: const TextStyle(color: AppTheme.textMuted),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: results.length,
                  itemBuilder: (context, idx) {
                    final u = results[idx];
                    final isMe = u.id == widget.user.id;
                    final isFollowing = _followingList.any((f) => f.id == u.id) || u.isFollowing;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        leading: _buildUserAvatar(
                          avatarUrl: u.fullAvatarUrl,
                          displayName: u.displayName,
                          radius: 22,
                          fontSize: 16,
                          backgroundColor: isMe ? AppTheme.accent : AppTheme.bg3,
                          textColor: isMe ? AppTheme.accentText : AppTheme.accentLight,
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                u.displayName,
                                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
                          (u.username != null && u.username!.trim().isNotEmpty)
                              ? '@${u.username!.replaceFirst('@', '').trim()}'
                              : '${u.trackCount} треков',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        trailing: isMe
                            ? null
                            : FilledButton.tonal(
                                style: FilledButton.styleFrom(
                                  backgroundColor: isFollowing ? AppTheme.bg3 : AppTheme.accent.withAlpha(50),
                                  foregroundColor: isFollowing ? AppTheme.textSecondary : AppTheme.accentLight,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                ),
                                onPressed: () async {
                                  if (isFollowing) {
                                    await _apiService.unfollowUser(u.id);
                                    setState(() {
                                      _followingList.removeWhere((f) => f.id == u.id);
                                      u.isFollowing = false;
                                    });
                                  } else {
                                    await _apiService.followUser(u.id);
                                    setState(() {
                                      u.isFollowing = true;
                                      _followingList.add(u);
                                    });
                                  }
                                },
                                child: Text(isFollowing ? 'Подписан' : 'Подписаться', style: const TextStyle(fontSize: 12)),
                              ),
                        onTap: () => _openUserProfile(u.id, initialUser: u),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _openUserProfile(int userId, {SocialUser? initialUser}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          userId: userId,
          initialUser: initialUser,
          audioHandler: widget.audioHandler,
        ),
      ),
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
