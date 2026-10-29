import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/track.dart';
import '../screens/artist_detail_screen.dart';
import '../services/api_service.dart';
import '../services/audio_player_handler.dart';
import '../theme/app_theme.dart';

class TrackTile extends StatefulWidget {
  final Track track;
  final bool isPlaying;
  final VoidCallback onTap;
  final AudioPlayerHandler? audioHandler;

  const TrackTile({
    super.key,
    required this.track,
    required this.isPlaying,
    required this.onTap,
    this.audioHandler,
  });

  @override
  State<TrackTile> createState() => _TrackTileState();
}

class _TrackTileState extends State<TrackTile> {
  final ApiService _apiService = ApiService();
  bool _isLikeLoading = false;

  Future<void> _toggleLike() async {
    setState(() => _isLikeLoading = true);
    try {
      final newStatus = await _apiService.toggleLike(widget.track.id, widget.track.isLiked);
      if (mounted) {
        setState(() {
          widget.track.isLiked = newStatus;
        });
      }
    } catch (_) {
      // Ignore
    } finally {
      if (mounted) {
        setState(() => _isLikeLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final isCurrent = widget.isPlaying;

    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Обложка трека
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 50,
                height: 50,
                child: track.fullCoverUrl != null
                    ? CachedNetworkImage(
                        imageUrl: track.fullCoverUrl!,
                        memCacheWidth: 120,
                        memCacheHeight: 120,
                        maxWidthDiskCache: 250,
                        maxHeightDiskCache: 250,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: AppTheme.bg3,
                          child: const Icon(Icons.music_note_rounded, color: AppTheme.textMuted, size: 24),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: AppTheme.bg3,
                          child: const Icon(Icons.music_note_rounded, color: AppTheme.textMuted, size: 24),
                        ),
                      )
                    : Container(
                        color: AppTheme.bg3,
                        child: const Icon(Icons.music_note_rounded, color: AppTheme.textMuted, size: 24),
                      ),
              ),
            ),
            const SizedBox(width: 14),

            // Название и артист
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? AppTheme.accentLight : AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.audioHandler != null
                        ? () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ArtistDetailScreen(
                                  artistName: track.artist,
                                  audioHandler: widget.audioHandler!,
                                ),
                              ),
                            );
                          }
                        : null,
                    child: Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: widget.audioHandler != null ? AppTheme.accentLight.withAlpha(220) : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Иконка играющего трека или длительность
            if (isCurrent) ...[
              const Icon(Icons.graphic_eq_rounded, color: AppTheme.accent, size: 22),
              const SizedBox(width: 8),
            ],

            // Лайк
            IconButton(
              icon: _isLikeLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(AppTheme.accent)),
                    )
                  : Icon(
                      track.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: track.isLiked ? AppTheme.accent : AppTheme.textMuted,
                      size: 20,
                    ),
              onPressed: _isLikeLoading ? null : _toggleLike,
            ),

            // Длительность
            Text(
              track.formattedDuration,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
