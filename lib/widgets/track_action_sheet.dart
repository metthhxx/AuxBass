import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../screens/artist_detail_screen.dart';
import '../services/api_service.dart';
import '../services/audio_player_handler.dart';
import '../theme/app_theme.dart';

class TrackActionSheet extends StatefulWidget {
  final Track track;
  final AudioPlayerHandler audioHandler;
  final VoidCallback? onLikeChanged;
  final int? playlistId;
  final VoidCallback? onRemoveFromPlaylist;

  const TrackActionSheet({
    super.key,
    required this.track,
    required this.audioHandler,
    this.onLikeChanged,
    this.playlistId,
    this.onRemoveFromPlaylist,
  });

  static Future<void> show(
    BuildContext context, {
    required Track track,
    required AudioPlayerHandler audioHandler,
    VoidCallback? onLikeChanged,
    int? playlistId,
    VoidCallback? onRemoveFromPlaylist,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bg1,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => TrackActionSheet(
        track: track,
        audioHandler: audioHandler,
        onLikeChanged: onLikeChanged,
        playlistId: playlistId,
        onRemoveFromPlaylist: onRemoveFromPlaylist,
      ),
    );
  }

  @override
  State<TrackActionSheet> createState() => _TrackActionSheetState();
}

class _TrackActionSheetState extends State<TrackActionSheet> {
  final ApiService _apiService = ApiService();
  bool _isLikeLoading = false;
  bool _isCaching = false;

  Future<void> _toggleLike() async {
    setState(() => _isLikeLoading = true);
    try {
      final newStatus = await _apiService.toggleLike(widget.track.id, widget.track.isLiked);
      if (mounted) {
        setState(() {
          widget.track.isLiked = newStatus;
        });
        widget.onLikeChanged?.call();
      }
    } catch (_) {
      // Ignore
    } finally {
      if (mounted) setState(() => _isLikeLoading = false);
    }
  }

  void _showAddToPlaylistDialog() async {
    Navigator.pop(context); // закрыть меню трека
    final playlistsFuture = _apiService.getPlaylists();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bg1,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (bCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Добавить в плейлист',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.add_rounded, size: 20, color: AppTheme.accentLight),
                        label: const Text('Создать', style: TextStyle(color: AppTheme.accentLight, fontWeight: FontWeight.bold)),
                        onPressed: () => _showCreatePlaylistAndAdd(bCtx),
                      ),
                    ],
                  ),
                ),
                const Divider(color: AppTheme.bg4),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.45,
                  ),
                  child: FutureBuilder<List<Playlist>>(
                    future: playlistsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24.0),
                            child: CircularProgressIndicator(color: AppTheme.accent),
                          ),
                        );
                      }
                      final list = snapshot.data ?? [];
                      if (list.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24.0),
                            child: Text('Плейлистов пока нет', style: TextStyle(color: AppTheme.textMuted)),
                          ),
                        );
                      }
                      return ListView.builder(
                        shrinkWrap: true,
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final pl = list[i];
                          return ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 44,
                                height: 44,
                                color: AppTheme.bg3,
                                child: pl.fullCoverUrl != null
                                    ? CachedNetworkImage(
                                        imageUrl: pl.fullCoverUrl!,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) => const Icon(Icons.queue_music_rounded, color: AppTheme.accentLight, size: 22),
                                      )
                                    : const Icon(Icons.queue_music_rounded, color: AppTheme.accentLight, size: 22),
                              ),
                            ),
                            title: Text(pl.name, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                            subtitle: Text('${pl.trackCount} треков', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                            onTap: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              Navigator.pop(bCtx);
                              try {
                                await _apiService.addTrackToPlaylist(pl.id, widget.track.id);
                                messenger.showSnackBar(
                                  SnackBar(content: Text('Трек добавлен в плейлист «${pl.name}»')),
                                );
                              } catch (e) {
                                messenger.showSnackBar(
                                  SnackBar(content: Text('Ошибка добавления: $e')),
                                );
                              }
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCreatePlaylistAndAdd(BuildContext bCtx) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: AppTheme.bg2,
        title: const Text('Новый плейлист', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Название плейлиста'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Отмена', style: TextStyle(color: AppTheme.textMuted)),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(dCtx);
              Navigator.pop(bCtx);
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              try {
                final created = await _apiService.createPlaylist(name);
                await _apiService.addTrackToPlaylist(created.id, widget.track.id);
                scaffoldMessenger.showSnackBar(
                  SnackBar(content: Text('Плейлист «$name» создан, трек добавлен')),
                );
              } catch (e) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(content: Text('Ошибка создания: $e')),
                );
              }
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }

  Future<void> _cacheTrack() async {
    setState(() => _isCaching = true);
    try {
      final streamUrl = await _apiService.getStreamUrl(widget.track.id);
      await widget.audioHandler.cacheService.cacheTrackInBackground(widget.track.id, streamUrl);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Трек сохранен в кэш для офлайн-прослушивания')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось кэшировать трек: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCaching = false);
    }
  }

  void _shareTrack() {
    Navigator.pop(context);
    final link = 'https://aux.ganj4craft.ru/track/${widget.track.id}';
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ссылка на трек скопирована в буфер обмена')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Шапка с информацией о треке
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 50,
                  height: 50,
                  child: track.fullCoverUrl != null
                      ? CachedNetworkImage(
                          imageUrl: track.fullCoverUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: AppTheme.bg3,
                            child: const Icon(Icons.music_note_rounded, color: AppTheme.textMuted),
                          ),
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
              title: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
              ),
              subtitle: Row(
                children: [
                  Flexible(
                    child: Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                    ),
                  ),
                  const Text(' • ', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                  Text(track.formattedDuration, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                  const Text(' • ', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                  const Icon(Icons.headphones_rounded, size: 13, color: AppTheme.textMuted),
                  const SizedBox(width: 3),
                  Text(track.formattedPlayCount, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                ],
              ),
              trailing: IconButton(
                icon: _isLikeLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
                      )
                    : Icon(
                        track.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: track.isLiked ? AppTheme.accent : AppTheme.textMuted,
                      ),
                onPressed: _isLikeLoading ? null : _toggleLike,
              ),
            ),
            const Divider(color: AppTheme.bg4),

            // Действия
            ListTile(
              leading: const Icon(Icons.queue_play_next_rounded, color: AppTheme.accentLight),
              title: const Text('Играть следующим', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                widget.audioHandler.playNext(track);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Трек будет воспроизведен следующим')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded, color: AppTheme.accentLight),
              title: const Text('Добавить в плейлист', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: _showAddToPlaylistDialog,
            ),
            ListTile(
              leading: const Icon(Icons.queue_music_rounded, color: AppTheme.accentLight),
              title: const Text('Добавить в конец очереди', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                widget.audioHandler.addToQueue(track);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Трек добавлен в конец очереди')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_rounded, color: AppTheme.accentLight),
              title: Text('Перейти к исполнителю ${track.artist}', style: const TextStyle(color: AppTheme.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ArtistDetailScreen(
                      artistName: track.artist,
                      audioHandler: widget.audioHandler,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_for_offline_rounded, color: AppTheme.accentLight),
              title: const Text('Сохранить в кэш', style: TextStyle(color: AppTheme.textPrimary)),
              trailing: _isCaching
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent))
                  : null,
              onTap: _isCaching ? null : _cacheTrack,
            ),
            ListTile(
              leading: const Icon(Icons.share_rounded, color: AppTheme.accentLight),
              title: const Text('Поделиться ссылкой', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: _shareTrack,
            ),

            if (widget.playlistId != null && widget.onRemoveFromPlaylist != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                title: const Text('Убрать из этого плейлиста', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(context);
                  widget.onRemoveFromPlaylist!();
                },
              ),
          ],
        ),
      ),
    );
  }
}
