import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../services/api_service.dart';
import '../services/audio_player_handler.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/track_tile.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final Playlist playlist;
  final AudioPlayerHandler audioHandler;
  final VoidCallback? onPlaylistDeleted;

  const PlaylistDetailScreen({
    super.key,
    required this.playlist,
    required this.audioHandler,
    this.onPlaylistDeleted,
  });

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  final ApiService _apiService = ApiService();
  late Playlist _currentPlaylist;
  List<Track> _tracks = [];
  bool _isLoading = true;
  bool _isReorderMode = false;

  @override
  void initState() {
    super.initState();
    _currentPlaylist = widget.playlist;
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    setState(() => _isLoading = true);
    try {
      final list = await _apiService.getPlaylistTracks(_currentPlaylist.id);
      if (mounted) {
        setState(() {
          _tracks = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _playAll({bool shuffle = false}) {
    if (_tracks.isEmpty) return;
    final list = List<Track>.from(_tracks);
    if (shuffle) list.shuffle();
    widget.audioHandler.playTrackList(list, 0);
  }

  Future<void> _renamePlaylist() async {
    final controller = TextEditingController(text: _currentPlaylist.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bg2,
        title: const Text('Переименовать плейлист', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Новое название'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: AppTheme.textMuted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != _currentPlaylist.name) {
      try {
        final updated = await _apiService.updatePlaylist(_currentPlaylist.id, newName);
        setState(() {
          _currentPlaylist = updated;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Плейлист переименован')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка обновления: $e')),
          );
        }
      }
    }
  }

  Future<void> _deletePlaylist() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bg2,
        title: const Text('Удалить плейлист?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'Вы уверены, что хотите удалить плейлист «${_currentPlaylist.name}»? Треки из медиатеки удалены не будут.',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена', style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _apiService.deletePlaylist(_currentPlaylist.id);
        widget.onPlaylistDeleted?.call();
        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Плейлист удален')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка удаления: $e')),
          );
        }
      }
    }
  }

  Future<void> _removeTrack(Track track) async {
    try {
      await _apiService.removeTrackFromPlaylist(_currentPlaylist.id, track.id);
      setState(() {
        _tracks.removeWhere((t) => t.id == track.id);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Трек «${track.title}» удален из плейлиста')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось удалить трек: $e')),
        );
      }
    }
  }

  void _onReorder(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    setState(() {
      final item = _tracks.removeAt(oldIndex);
      _tracks.insert(newIndex, item);
    });

    try {
      final ids = _tracks.map((t) => t.id).toList();
      await _apiService.reorderPlaylistTracks(_currentPlaylist.id, ids);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось сохранить новый порядок: $e')),
        );
      }
    }
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
        actions: [
          if (_tracks.length > 1)
            IconButton(
              icon: Icon(
                _isReorderMode ? Icons.done_rounded : Icons.swap_vert_rounded,
                color: _isReorderMode ? AppTheme.accentLight : AppTheme.textSecondary,
              ),
              tooltip: _isReorderMode ? 'Готово' : 'Изменить порядок',
              onPressed: () => setState(() => _isReorderMode = !_isReorderMode),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: AppTheme.textPrimary),
            color: AppTheme.bg2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (val) {
              if (val == 'rename') _renamePlaylist();
              if (val == 'delete') _deletePlaylist();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(Icons.edit_rounded, color: AppTheme.textSecondary, size: 20),
                    SizedBox(width: 12),
                    Text('Переименовать', style: TextStyle(color: AppTheme.textPrimary)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                    SizedBox(width: 12),
                    Text('Удалить плейлист', style: TextStyle(color: Colors.redAccent)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
                : CustomScrollView(
                    slivers: [
                      // Шапка плейлиста
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          child: Column(
                            children: [
                              // Большая обложка
                              Container(
                                width: 140,
                                height: 140,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  color: AppTheme.bg3,
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black45,
                                      blurRadius: 20,
                                      offset: Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: _currentPlaylist.fullCoverUrl != null
                                      ? CachedNetworkImage(
                                          imageUrl: _currentPlaylist.fullCoverUrl!,
                                          fit: BoxFit.cover,
                                          errorWidget: (_, __, ___) => const Icon(
                                            Icons.queue_music_rounded,
                                            size: 64,
                                            color: AppTheme.accentLight,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.queue_music_rounded,
                                          size: 64,
                                          color: AppTheme.accentLight,
                                        ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Название
                              Text(
                                _currentPlaylist.name,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),

                              // Количество треков
                              Text(
                                '${_tracks.length} треков',
                                style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                              ),
                              const SizedBox(height: 16),

                              // Кнопки управления
                              if (_tracks.isNotEmpty)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: AppTheme.accent,
                                        foregroundColor: AppTheme.accentText,
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      ),
                                      onPressed: () => _playAll(shuffle: false),
                                      icon: const Icon(Icons.play_arrow_rounded, size: 24),
                                      label: const Text('Слушать', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    ),
                                    const SizedBox(width: 12),
                                    IconButton.filledTonal(
                                      style: IconButton.styleFrom(
                                        backgroundColor: AppTheme.bg2,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                        padding: const EdgeInsets.all(12),
                                      ),
                                      onPressed: () => _playAll(shuffle: true),
                                      icon: const Icon(Icons.shuffle_rounded, size: 24, color: AppTheme.textPrimary),
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ),

                      // Список треков
                      if (_tracks.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.queue_music_rounded, size: 56, color: AppTheme.bg4),
                                SizedBox(height: 12),
                                Text('В этом плейлисте пока нет треков', style: TextStyle(color: AppTheme.textMuted)),
                                SizedBox(height: 4),
                                Text('Добавляйте треки через меню «···» у любого трека', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                              ],
                            ),
                          ),
                        )
                      else if (_isReorderMode)
                        SliverToBoxAdapter(
                          child: ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _tracks.length,
                            onReorder: _onReorder,
                            itemBuilder: (context, index) {
                              final track = _tracks[index];
                              return ListTile(
                                key: ValueKey('reorder_${track.id}'),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                leading: const Icon(Icons.drag_handle_rounded, color: AppTheme.accentLight),
                                title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                                subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                                trailing: IconButton(
                                  icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.redAccent, size: 20),
                                  onPressed: () => _removeTrack(track),
                                ),
                              );
                            },
                          ),
                        )
                      else
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final track = _tracks[index];
                              return ValueListenableBuilder<Track?>(
                                valueListenable: widget.audioHandler.currentTrackNotifier,
                                builder: (context, current, _) {
                                  final isCurrent = current?.id == track.id;
                                  return TrackTile(
                                    track: track,
                                    isPlaying: isCurrent,
                                    audioHandler: widget.audioHandler,
                                    playlistId: _currentPlaylist.id,
                                    onRemoveFromPlaylist: () => _removeTrack(track),
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
                    ],
                  ),
          ),
          MiniPlayer(audioHandler: widget.audioHandler),
        ],
      ),
    );
  }
}
