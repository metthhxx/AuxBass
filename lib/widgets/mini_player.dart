import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import '../screens/now_playing_screen.dart';
import '../services/audio_player_handler.dart';
import '../theme/app_theme.dart';

class MiniPlayer extends StatelessWidget {
  final AudioPlayerHandler audioHandler;

  const MiniPlayer({super.key, required this.audioHandler});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<Track?>(
        valueListenable: audioHandler.currentTrackNotifier,
        builder: (context, track, _) {
          if (track == null) return const SizedBox.shrink();

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
            child: GestureDetector(
            // Свайпы на мини-плеере: свайп влево — следующий трек, свайп вправо — предыдущий
            onHorizontalDragEnd: (details) {
              final v = details.primaryVelocity;
              if (v != null) {
                if (v < -200) {
                  audioHandler.skipToNext();
                } else if (v > 200) {
                  audioHandler.skipToPrevious();
                }
              }
            },
            onTap: () {
              Navigator.of(context).push(
                PageRouteBuilder(
                  transitionDuration: const Duration(milliseconds: 350),
                  reverseTransitionDuration: const Duration(milliseconds: 280),
                  pageBuilder: (context, anim, _) => NowPlayingScreen(audioHandler: audioHandler),
                  transitionsBuilder: (context, anim, _, child) {
                    final curvedAnim = CurvedAnimation(
                      parent: anim,
                      curve: Curves.easeOutCubic,
                      reverseCurve: Curves.easeInCubic,
                    );
                    // Анимация плавного расширения прямо из окошка мини-плеера
                    return FadeTransition(
                      opacity: curvedAnim,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.22, end: 1.0).animate(curvedAnim),
                        alignment: const Alignment(0, 0.88),
                        child: child,
                      ),
                    );
                  },
                ),
              );
            },
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.bg2,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 14,
                    offset: Offset(0, 4),
                  ),
                ],
                border: Border.all(color: AppTheme.bg4),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    // Тонкая полоска прогресса воспроизведения сверху
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: StreamBuilder<Duration>(
                        stream: audioHandler.player.positionStream,
                        builder: (context, snapshot) {
                          final pos = snapshot.data ?? Duration.zero;
                          final total = audioHandler.player.duration ?? Duration(seconds: track.duration);
                          final ratio = total.inMilliseconds > 0
                              ? (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
                              : 0.0;

                          return LinearProgressIndicator(
                            value: ratio,
                            minHeight: 2.5,
                            backgroundColor: Colors.transparent,
                            valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
                          );
                        },
                      ),
                    ),

                    // Содержимое мини-плеера
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10.0),
                      child: Row(
                        children: [
                          // Обложка трека с Hero-анимацией (плавный зум в большой плеер)
                          Hero(
                            tag: 'now_playing_cover',
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(
                                width: 46,
                                height: 46,
                                child: track.fullCoverUrl != null
                                    ? CachedNetworkImage(
                                        imageUrl: track.fullCoverUrl!,
                                        fit: BoxFit.cover,
                                        placeholder: (_, __) => Container(
                                          color: AppTheme.bg3,
                                          child: const Icon(Icons.music_note_rounded, size: 22, color: AppTheme.textMuted),
                                        ),
                                        errorWidget: (_, __, ___) => Container(
                                          color: AppTheme.bg3,
                                          child: const Icon(Icons.music_note_rounded, size: 22, color: AppTheme.textMuted),
                                        ),
                                      )
                                    : Container(
                                        color: AppTheme.bg3,
                                        child: const Icon(Icons.music_note_rounded, size: 22, color: AppTheme.textMuted),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Название и артист
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Кнопка Play/Pause
                          StreamBuilder<PlayerState>(
                            stream: audioHandler.player.playerStateStream,
                            builder: (context, snapshot) {
                              final isPlaying = snapshot.data?.playing ?? false;
                              return IconButton(
                                icon: Icon(
                                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  color: AppTheme.accentLight,
                                  size: 32,
                                ),
                                onPressed: () {
                                  if (isPlaying) {
                                    audioHandler.pause();
                                  } else {
                                    audioHandler.play();
                                  }
                                },
                              );
                            },
                          ),

                          // Кнопка Следующий трек
                          IconButton(
                            icon: const Icon(
                              Icons.skip_next_rounded,
                              color: AppTheme.textPrimary,
                              size: 26,
                            ),
                            onPressed: () => audioHandler.skipToNext(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
}
