import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/album.dart';
import '../models/track.dart';
import '../services/api_service.dart';
import '../services/audio_player_handler.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/track_action_sheet.dart';
import 'artist_detail_screen.dart';

class AlbumDetailScreen extends StatefulWidget {
  final dynamic albumId;
  final Album? initialAlbum;
  final AudioPlayerHandler audioHandler;

  const AlbumDetailScreen({
    super.key,
    required this.albumId,
    this.initialAlbum,
    required this.audioHandler,
  });

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  final ApiService _apiService = ApiService();
  Album? _album;
  bool _isLoading = true;
  String? _error;
  bool _isAddingAll = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialAlbum != null && widget.initialAlbum!.tracks.isNotEmpty) {
      _album = widget.initialAlbum;
      _isLoading = false;
    } else {
      _loadAlbum();
    }
  }

  Future<void> _loadAlbum() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final alb = await _apiService.getAlbumDetails(widget.albumId);
      if (mounted) {
        setState(() {
          _album = alb;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Не удалось загрузить данные альбома';
          _isLoading = false;
        });
      }
    }
  }

  void _playAlbum({bool shuffle = false}) {
    if (_album == null || _album!.tracks.isEmpty) return;
    final list = List<Track>.from(_album!.tracks);
    if (shuffle) {
      list.shuffle();
    }
    widget.audioHandler.playTrackList(list, 0);
  }

  Future<void> _addAllToLibrary() async {
    if (_album == null || _album!.tracks.isEmpty) return;
    setState(() => _isAddingAll = true);
    int added = 0;
    for (final t in _album!.tracks) {
      final success = await _apiService.addTrackToLibrary(t.id);
      if (success) added++;
    }
    if (mounted) {
      setState(() => _isAddingAll = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Добавлено треков в библиотеку: $added'),
          backgroundColor: AppTheme.bg3,
          behavior: SnackBarBehavior.floating,
        ),
      );
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
        title: Text(
          _album?.title ?? 'Альбом',
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
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.album_outlined, size: 60, color: AppTheme.textMuted),
                            const SizedBox(height: 12),
                            Text(_error!, style: const TextStyle(color: AppTheme.textSecondary)),
                            const SizedBox(height: 16),
                            FilledButton.tonal(onPressed: _loadAlbum, child: const Text('Повторить')),
                          ],
                        ),
                      )
                    : _buildContent(),
          ),
          MiniPlayer(audioHandler: widget.audioHandler),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final album = _album!;
    final cover = album.coverUrl ?? (album.tracks.isNotEmpty ? album.tracks.first.fullCoverUrl : null);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              children: [
                // Обложка альбома
                Center(
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(128),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: cover != null
                          ? CachedNetworkImage(
                              imageUrl: cover,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: AppTheme.bg2,
                                child: const Icon(Icons.album_rounded, size: 80, color: AppTheme.textMuted),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: AppTheme.bg2,
                                child: const Icon(Icons.album_rounded, size: 80, color: AppTheme.textMuted),
                              ),
                            )
                          : Container(
                              color: AppTheme.bg2,
                              child: const Icon(Icons.album_rounded, size: 80, color: AppTheme.textMuted),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Название альбома
                Text(
                  album.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),

                // Артист (кликабельный)
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ArtistDetailScreen(
                          artistName: album.artist,
                          audioHandler: widget.audioHandler,
                        ),
                      ),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        album.artist,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.accentLight,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded, size: 18, color: AppTheme.accentLight),
                    ],
                  ),
                ),
                const SizedBox(height: 6),

                // Метаинформация (год, кол-во треков)
                Text(
                  [
                    if (album.year != null && album.year! > 0) '${album.year} год',
                    '${album.tracks.length} ${album.tracks.length == 1 ? "трек" : (album.tracks.length > 1 && album.tracks.length < 5 ? "трека" : "треков")}',
                  ].join(' • '),
                  style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 18),

                // Кнопки действий: Слушать, Шафл, Добавить
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () => _playAlbum(shuffle: false),
                      icon: const Icon(Icons.play_arrow_rounded, size: 24),
                      label: const Text('Слушать', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.bg4),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () => _playAlbum(shuffle: true),
                      icon: const Icon(Icons.shuffle_rounded, size: 20, color: AppTheme.textPrimary),
                      label: const Text('Шафл', style: TextStyle(color: AppTheme.textPrimary)),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      onPressed: _isAddingAll ? null : _addAllToLibrary,
                      style: IconButton.styleFrom(
                        backgroundColor: AppTheme.bg2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: _isAddingAll
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
                            )
                          : const Icon(Icons.bookmark_add_outlined, color: AppTheme.textPrimary),
                      tooltip: 'Добавить альбом в медиатеку',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Список треков
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final track = album.tracks[index];
                return ValueListenableBuilder<Track?>(
                  valueListenable: widget.audioHandler.currentTrackNotifier,
                  builder: (context, currentTrack, _) {
                    final isPlaying = currentTrack?.id == track.id;
                    return InkWell(
                      onTap: () {
                        widget.audioHandler.playTrackList(album.tracks, index);
                      },
                      onLongPress: () {
                        TrackActionSheet.show(
                          context,
                          track: track,
                          audioHandler: widget.audioHandler,
                          onLikeChanged: () => setState(() {}),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                        child: Row(
                          children: [
                            // Номер трека
                            SizedBox(
                              width: 28,
                              child: isPlaying
                                  ? const Icon(Icons.graphic_eq_rounded, color: AppTheme.accent, size: 20)
                                  : Text(
                                      '${index + 1}',
                                      style: const TextStyle(
                                        color: AppTheme.textMuted,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 8),

                            // Название и артист
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isPlaying ? AppTheme.accentLight : AppTheme.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    track.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),

                            // Длительность
                            Text(
                              track.formattedDuration,
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                            ),

                            // Кнопка действий
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.more_vert_rounded, color: AppTheme.textMuted, size: 20),
                              onPressed: () {
                                TrackActionSheet.show(
                                  context,
                                  track: track,
                                  audioHandler: widget.audioHandler,
                                  onLikeChanged: () => setState(() {}),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
              childCount: album.tracks.length,
            ),
          ),
        ),
      ],
    );
  }
}
