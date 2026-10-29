import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/album.dart';
import '../models/playlist.dart';
import '../models/social_user.dart';
import '../models/track.dart';
import '../services/api_service.dart';
import '../services/audio_player_handler.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/track_tile.dart';
import 'album_detail_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final int userId;
  final SocialUser? initialUser;
  final AudioPlayerHandler audioHandler;

  const UserProfileScreen({
    super.key,
    required this.userId,
    this.initialUser,
    required this.audioHandler,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final ApiService _apiService = ApiService();
  SocialUser? _user;
  List<Track> _tracks = [];
  List<Playlist> _playlists = [];
  List<Album> _albums = [];
  bool _isLoading = true;
  bool _isFollowLoading = false;
  int _activeTab = 0; // 0: Треки, 1: Плейлисты, 2: Альбомы

  @override
  void initState() {
    super.initState();
    _user = widget.initialUser;
    _loadAllUserData();
  }

  Future<void> _loadAllUserData() async {
    setState(() => _isLoading = true);
    try {
      final userFuture = _apiService.getUserProfile(widget.userId);
      final tracksFuture = _apiService.getUserLibrary(widget.userId);
      final playlistsFuture = _apiService.getUserPlaylists(widget.userId);
      final albumsFuture = _apiService.getUserAlbums(widget.userId);

      final results = await Future.wait([
        userFuture.catchError((_) => widget.initialUser ?? SocialUser(id: widget.userId)),
        tracksFuture.catchError((_) => <Track>[]),
        playlistsFuture.catchError((_) => <Playlist>[]),
        albumsFuture.catchError((_) => <Album>[]),
      ]);

      if (mounted) {
        setState(() {
          _user = results[0] as SocialUser;
          _tracks = results[1] as List<Track>;
          _playlists = results[2] as List<Playlist>;
          _albums = results[3] as List<Album>;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFollow() async {
    if (_user == null || _isFollowLoading) return;
    setState(() => _isFollowLoading = true);
    final currentlyFollowing = _user!.isFollowing;
    final success = currentlyFollowing
        ? await _apiService.unfollowUser(_user!.id)
        : await _apiService.followUser(_user!.id);

    if (mounted) {
      setState(() {
        _isFollowLoading = false;
        if (success) {
          _user!.isFollowing = !currentlyFollowing;
        }
      });
    }
  }

  void _playAll({bool shuffle = false}) {
    if (_tracks.isEmpty) return;
    final list = List<Track>.from(_tracks);
    if (shuffle) list.shuffle();
    widget.audioHandler.playTrackList(list, 0);
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
        title: Text(
          _user?.displayName ?? 'Профиль',
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
                : _buildProfileContent(),
          ),
          MiniPlayer(audioHandler: widget.audioHandler),
        ],
      ),
    );
  }

  Widget _buildProfileContent() {
    final user = _user!;
    return CustomScrollView(
      slivers: [
        // Карточка пользователя
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              children: [
                // Аватар
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(77),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: user.fullAvatarUrl != null
                        ? CachedNetworkImage(
                            imageUrl: user.fullAvatarUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: AppTheme.bg3,
                              child: Center(
                                child: Text(
                                  user.displayName.replaceFirst(RegExp(r'^@+'), '').trim().characters.firstOrNull?.toUpperCase() ?? 'U',
                                  style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: AppTheme.accentLight),
                                ),
                              ),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: AppTheme.bg3,
                              child: Center(
                                child: Text(
                                  user.displayName.replaceFirst(RegExp(r'^@+'), '').trim().characters.firstOrNull?.toUpperCase() ?? 'U',
                                  style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: AppTheme.accentLight),
                                ),
                              ),
                            ),
                          )
                        : Container(
                            color: AppTheme.bg3,
                            child: Center(
                              child: Text(
                                user.displayName.replaceFirst(RegExp(r'^@+'), '').trim().characters.firstOrNull?.toUpperCase() ?? 'U',
                                style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: AppTheme.accentLight),
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 14),

                // Имя
                Text(
                  user.displayName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (user.username != null && user.username!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '@${user.username!.replaceFirst('@', '').trim()}',
                    style: const TextStyle(fontSize: 14, color: AppTheme.accentLight),
                  ),
                ],

                // Канал
                if (user.channelTitle != null && user.channelTitle!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.bg2,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.campaign_rounded, size: 16, color: AppTheme.textMuted),
                        const SizedBox(width: 6),
                        Text(
                          user.channelTitle!,
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // Статистика (счетчики)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildStatCol('${_tracks.isNotEmpty ? _tracks.length : user.trackCount}', 'Треков'),
                    const SizedBox(width: 24),
                    _buildStatCol('${user.followersCount}', 'Подписчиков'),
                    const SizedBox(width: 24),
                    _buildStatCol('${user.followingCount}', 'Подписок'),
                  ],
                ),
                const SizedBox(height: 18),

                // Кнопки: Подписаться, Слушать, Шафл
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: user.isFollowing ? AppTheme.bg3 : AppTheme.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _isFollowLoading ? null : _toggleFollow,
                      child: _isFollowLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              user.isFollowing ? 'Вы подписаны' : 'Подписаться',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                    if (_tracks.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.bg2,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => _playAll(shuffle: false),
                        icon: const Icon(Icons.play_arrow_rounded, size: 20, color: AppTheme.accentLight),
                        label: const Text('Слушать', style: TextStyle(color: AppTheme.textPrimary)),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filledTonal(
                        style: IconButton.styleFrom(
                          backgroundColor: AppTheme.bg2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () => _playAll(shuffle: true),
                        icon: const Icon(Icons.shuffle_rounded, size: 20, color: AppTheme.textPrimary),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 18),

                // Табы контента пользователя
                Row(
                  children: [
                    _buildSubTab(0, 'Треки (${_tracks.length})'),
                    const SizedBox(width: 8),
                    _buildSubTab(1, 'Плейлисты (${_playlists.length})'),
                    const SizedBox(width: 8),
                    _buildSubTab(2, 'Альбомы (${_albums.length})'),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Содержимое активного таба
        if (_activeTab == 0) ...[
          if (_tracks.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(40.0),
                child: Center(
                  child: Text('У пользователя пока нет треков', style: TextStyle(color: AppTheme.textMuted)),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final track = _tracks[index];
                    return ValueListenableBuilder<Track?>(
                      valueListenable: widget.audioHandler.currentTrackNotifier,
                      builder: (context, currentTrack, _) {
                        final isPlaying = currentTrack?.id == track.id;
                        return TrackTile(
                          track: track,
                          isPlaying: isPlaying,
                          onTap: () {
                            widget.audioHandler.playTrackList(_tracks, index);
                          },
                        );
                      },
                    );
                  },
                  childCount: _tracks.length,
                ),
              ),
            ),
        ] else if (_activeTab == 1) ...[
          if (_playlists.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(40.0),
                child: Center(
                  child: Text('У пользователя нет публичных плейлистов', style: TextStyle(color: AppTheme.textMuted)),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final pl = _playlists[index];
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.bg2,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.bg3,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.queue_music_rounded, color: AppTheme.accentLight),
                        ),
                        title: Text(pl.name, style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                        subtitle: Text('${pl.trackCount} треков', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                        onTap: () async {
                          final tracks = await _apiService.getPlaylistTracks(pl.id);
                          if (tracks.isNotEmpty) {
                            widget.audioHandler.playTrackList(tracks, 0);
                          }
                        },
                      ),
                    );
                  },
                  childCount: _playlists.length,
                ),
              ),
            ),
        ] else if (_activeTab == 2) ...[
          if (_albums.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(40.0),
                child: Center(
                  child: Text('У пользователя нет добавленных альбомов', style: TextStyle(color: AppTheme.textMuted)),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.78,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final alb = _albums[index];
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
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: _albums.length,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildStatCol(String count, String label) {
    return Column(
      children: [
        Text(
          count,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _buildSubTab(int index, String title) {
    final isSelected = _activeTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.accent.withAlpha(50) : AppTheme.bg2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppTheme.accent : Colors.transparent,
              width: 1,
            ),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? AppTheme.accentLight : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
