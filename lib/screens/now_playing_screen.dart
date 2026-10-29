import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import '../services/api_service.dart';
import '../services/audio_player_handler.dart';
import '../theme/app_theme.dart';
import '../widgets/track_action_sheet.dart';

class NowPlayingScreen extends StatefulWidget {
  final AudioPlayerHandler audioHandler;

  const NowPlayingScreen({super.key, required this.audioHandler});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  final ApiService _apiService = ApiService();
  double? _dragPosition;

  String _formatTime(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg0,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32, color: AppTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Column(
          children: [
            Text(
              'СЕЙЧАС ИГРАЕТ',
              style: TextStyle(fontSize: 11, letterSpacing: 1.5, color: AppTheme.textSecondary, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 2),
            Text(
              'AuxBass Music',
              style: TextStyle(fontSize: 13, color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          ValueListenableBuilder<Track?>(
            valueListenable: widget.audioHandler.currentTrackNotifier,
            builder: (context, currentTrack, _) {
              if (currentTrack == null) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.more_vert_rounded, size: 26, color: AppTheme.textPrimary),
                onPressed: () {
                  TrackActionSheet.show(
                    context,
                    track: currentTrack,
                    audioHandler: widget.audioHandler,
                    onLikeChanged: () => setState(() {}),
                  );
                },
              );
            },
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // Свайпы: влево/вправо — переключение треков, свайп вниз — свернуть плеер
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity;
          if (v != null) {
            if (v < -200) {
              widget.audioHandler.skipToNext();
            } else if (v > 200) {
              widget.audioHandler.skipToPrevious();
            }
          }
        },
        onVerticalDragEnd: (details) {
          final v = details.primaryVelocity;
          if (v != null && v > 150) {
            Navigator.of(context).pop();
          }
        },
        child: ValueListenableBuilder<Track?>(
          valueListenable: widget.audioHandler.currentTrackNotifier,
          builder: (context, currentTrack, _) {
            if (currentTrack == null) {
              return const Center(child: Text('Ничего не играет', style: TextStyle(color: AppTheme.textSecondary)));
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Большая обложка с Hero-анимацией расширения
                    Center(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Hero(
                          tag: 'now_playing_cover',
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black54,
                                  blurRadius: 30,
                                  offset: Offset(0, 15),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: currentTrack.fullCoverUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: currentTrack.fullCoverUrl!,
                                      fit: BoxFit.cover,
                                      placeholder: (_, __) => Container(
                                        color: AppTheme.bg3,
                                        child: const Icon(Icons.music_note_rounded, size: 80, color: AppTheme.textMuted),
                                      ),
                                      errorWidget: (_, __, ___) => Container(
                                        color: AppTheme.bg3,
                                        child: const Icon(Icons.music_note_rounded, size: 80, color: AppTheme.textMuted),
                                      ),
                                    )
                                  : Container(
                                      color: AppTheme.bg3,
                                      child: const Icon(Icons.music_note_rounded, size: 80, color: AppTheme.textMuted),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Название трека и автор + кнопка Like
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentTrack.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              currentTrack.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          currentTrack.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: currentTrack.isLiked ? AppTheme.accent : AppTheme.textSecondary,
                          size: 28,
                        ),
                        onPressed: () async {
                          final newStatus = await _apiService.toggleLike(currentTrack.id, currentTrack.isLiked);
                          setState(() {
                            currentTrack.isLiked = newStatus;
                          });
                        },
                      ),
                    ],
                  ),

                  // Полоса прогресса воспроизведения (Scrubber)
                  StreamBuilder<Duration>(
                    stream: widget.audioHandler.player.positionStream,
                    builder: (context, snapshot) {
                      final position = snapshot.data ?? Duration.zero;
                      final total = widget.audioHandler.player.duration ?? Duration(seconds: currentTrack.duration);

                      final maxVal = total.inMilliseconds.toDouble();
                      final currentVal = _dragPosition ?? position.inMilliseconds.toDouble().clamp(0.0, maxVal);

                      return Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: AppTheme.accent,
                              inactiveTrackColor: AppTheme.bg4,
                              thumbColor: AppTheme.accentLight,
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                            ),
                            child: Slider(
                              value: currentVal > maxVal ? maxVal : currentVal,
                              max: maxVal > 0 ? maxVal : 1.0,
                              onChanged: (val) {
                                setState(() {
                                  _dragPosition = val;
                                });
                              },
                              onChangeEnd: (val) {
                                widget.audioHandler.seek(Duration(milliseconds: val.toInt()));
                                setState(() {
                                  _dragPosition = null;
                                });
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_formatTime(position), style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                                Text(_formatTime(total), style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  // Кнопки управления плеером
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Перемешивание (Shuffle)
                      IconButton(
                        icon: Icon(
                          Icons.shuffle_rounded,
                          color: widget.audioHandler.isShuffle ? AppTheme.accent : AppTheme.textMuted,
                          size: 26,
                        ),
                        onPressed: () {
                          widget.audioHandler.toggleShuffle();
                          setState(() {});
                        },
                      ),

                      // Предыдущий трек
                      IconButton(
                        icon: const Icon(Icons.skip_previous_rounded, color: AppTheme.textPrimary, size: 38),
                        onPressed: () => widget.audioHandler.skipToPrevious(),
                      ),

                      // Play / Pause (большая зеленая кнопка)
                      StreamBuilder<PlayerState>(
                        stream: widget.audioHandler.player.playerStateStream,
                        builder: (context, snapshot) {
                          final state = snapshot.data;
                          final isPlaying = state?.playing ?? false;
                          final isBuffering = state?.processingState == ProcessingState.buffering ||
                              state?.processingState == ProcessingState.loading;

                          return GestureDetector(
                            onTap: () {
                              if (isPlaying) {
                                widget.audioHandler.pause();
                              } else {
                                widget.audioHandler.play();
                              }
                            },
                            child: Container(
                              width: 68,
                              height: 68,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.accent,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.accentGlow,
                                    blurRadius: 16,
                                    offset: Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: isBuffering
                                  ? const Center(
                                      child: SizedBox(
                                        width: 28,
                                        height: 28,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 3,
                                          valueColor: AlwaysStoppedAnimation(AppTheme.accentText),
                                        ),
                                      ),
                                    )
                                  : Icon(
                                      isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                      size: 40,
                                      color: AppTheme.accentText,
                                    ),
                            ),
                          );
                        },
                      ),

                      // Следующий трек
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded, color: AppTheme.textPrimary, size: 38),
                        onPressed: () => widget.audioHandler.skipToNext(),
                      ),

                      // Повтор (Repeat)
                      IconButton(
                        icon: Icon(
                          widget.audioHandler.loopMode == LoopMode.one
                              ? Icons.repeat_one_rounded
                              : Icons.repeat_rounded,
                          color: widget.audioHandler.loopMode != LoopMode.off ? AppTheme.accent : AppTheme.textMuted,
                          size: 26,
                        ),
                        onPressed: () {
                          widget.audioHandler.toggleLoopMode();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}
}
