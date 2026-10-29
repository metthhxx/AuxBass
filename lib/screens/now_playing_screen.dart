import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import '../screens/artist_detail_screen.dart';
import '../services/api_service.dart';
import '../services/audio_player_handler.dart';
import '../services/player_settings_service.dart';
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
  bool _isLikeLoading = false;

  String _formatTime(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _toggleLike(Track currentTrack) async {
    setState(() => _isLikeLoading = true);
    try {
      final newStatus = await _apiService.toggleLike(currentTrack.id, currentTrack.isLiked);
      if (mounted) {
        setState(() {
          currentTrack.isLiked = newStatus;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLikeLoading = false);
    }
  }

  void _showLyricsSheet(BuildContext context, Track track) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14161C),
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) {
            return FutureBuilder<Map<String, dynamic>?>(
              future: _apiService.getTrackLyrics(track.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(Color(0xFF22E066)),
                    ),
                  );
                }
                final data = snapshot.data;
                final plain = data?['plain_lyrics'] as String?;
                final synced = data?['synced_lyrics'] as String?;
                final lyricsText = (plain?.trim().isNotEmpty == true)
                    ? plain!.trim()
                    : (synced?.trim().isNotEmpty == true)
                        ? synced!.replaceAll(RegExp(r'\[.*?\]'), '').trim()
                        : null;

                if (lyricsText == null || lyricsText.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lyrics_outlined, size: 48, color: AppTheme.textMuted),
                          const SizedBox(height: 12),
                          const Text(
                            'Текст песни не найден',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Для трека «${track.title}» пока нет текста в базе',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  children: [
                    Text(
                      track.title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artist,
                      style: const TextStyle(fontSize: 14, color: Color(0xFF22E066), fontWeight: FontWeight.w500),
                    ),
                    const Divider(color: Color(0x22FFFFFF), height: 28),
                    SelectableText(
                      lyricsText,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.8,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFE0E0E0),
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

  void _showQueueSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14161C),
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) {
            return ValueListenableBuilder<List<Track>>(
              valueListenable: widget.audioHandler.queueNotifier,
              builder: (context, queue, _) {
                if (queue.isEmpty) {
                  return const Center(
                    child: Text('Очередь воспроизведения пуста', style: TextStyle(color: AppTheme.textMuted)),
                  );
                }
                final current = widget.audioHandler.currentTrack;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Очередь (${queue.length} треков)',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          TextButton(
                            onPressed: () {
                              widget.audioHandler.toggleShuffle();
                              setState(() {});
                            },
                            child: Text(
                              widget.audioHandler.isShuffle ? 'Шафл вкл' : 'Перемешать',
                              style: const TextStyle(color: Color(0xFF22E066), fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Color(0x22FFFFFF), height: 1),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: queue.length,
                        itemBuilder: (context, i) {
                          final tr = queue[i];
                          final isCur = tr.id == current?.id;
                          return ListTile(
                            selected: isCur,
                            selectedTileColor: const Color(0x1A22E066),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 42,
                                height: 42,
                                child: tr.fullCoverUrl != null
                                    ? CachedNetworkImage(
                                        imageUrl: tr.fullCoverUrl!,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) => const Icon(Icons.music_note_rounded, color: AppTheme.textMuted),
                                      )
                                    : const Icon(Icons.music_note_rounded, color: AppTheme.textMuted),
                              ),
                            ),
                            title: Text(
                              tr.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isCur ? const Color(0xFF22E066) : Colors.white,
                                fontWeight: isCur ? FontWeight.bold : FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              '${tr.artist} • ${tr.formattedDuration}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Color(0xFF888E99), fontSize: 12),
                            ),
                            trailing: isCur
                                ? const Icon(Icons.graphic_eq_rounded, color: Color(0xFF22E066), size: 20)
                                : null,
                            onTap: () {
                              widget.audioHandler.playTrackList(queue, i);
                              Navigator.pop(ctx);
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

  Widget _buildGlassButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 42,
    double iconSize = 20,
    Color? iconColor,
    Color? activeGlowColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0x14FFFFFF),
          border: Border.all(color: const Color(0x1FFFFFFF)),
          boxShadow: [
            const BoxShadow(
              color: Color(0x66000000),
              blurRadius: 6,
              offset: Offset(2, 3),
            ),
            if (activeGlowColor != null)
              BoxShadow(
                color: activeGlowColor.withAlpha(102),
                blurRadius: 10,
              ),
          ],
        ),
        child: Center(
          child: Icon(icon, size: iconSize, color: iconColor ?? Colors.white),
        ),
      ),
    );
  }

  Widget _buildNeumorphicButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 48,
    double iconSize = 24,
    bool isActive = false,
  }) {
    const activeColor = Color(0xFF22E066);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive ? const Color(0x2E22E066) : const Color(0x14FFFFFF),
          border: Border.all(
            color: isActive ? const Color(0x9922E066) : const Color(0x1FFFFFFF),
          ),
          boxShadow: [
            const BoxShadow(
              color: Color(0x66000000),
              blurRadius: 6,
              offset: Offset(2, 3),
            ),
            if (isActive)
              const BoxShadow(
                color: Color(0x5922E066),
                blurRadius: 10,
              ),
          ],
        ),
        child: Center(
          child: Icon(
            icon,
            size: iconSize,
            color: isActive ? activeColor : Colors.white,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlayerStyle>(
      valueListenable: PlayerSettingsService.playerStyleNotifier,
      builder: (context, style, _) {
        return ValueListenableBuilder<Track?>(
          valueListenable: widget.audioHandler.currentTrackNotifier,
          builder: (context, currentTrack, _) {
            if (currentTrack == null) {
              return const Scaffold(
                backgroundColor: AppTheme.bg0,
                body: Center(
                  child: Text('Ничего не играет', style: TextStyle(color: AppTheme.textSecondary)),
                ),
              );
            }

            if (style == PlayerStyle.web) {
              return _buildWebPlayer(currentTrack);
            } else {
              return _buildNativePlayer(currentTrack);
            }
          },
        );
      },
    );
  }

  // ================= 1. ВЕБ-ПЛЕЕР AUXBASS (КАК НА САЙТЕ AUX.GANJ4CRAFT.RU) =================
  Widget _buildWebPlayer(Track currentTrack) {
    final screenWidth = MediaQuery.of(context).size.width;
    final coverSize = (screenWidth - 68).clamp(180.0, 310.0);

    return Scaffold(
      backgroundColor: const Color(0xFF090A0C),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
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
        child: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.75),
              radius: 1.25,
              colors: [
                Color(0xFF1E2129),
                Color(0xFF121419),
                Color(0xFF090A0C),
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Верхний индикатор свайпа вниз (Swipe pill)
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 44,
                      height: 5,
                      margin: const EdgeInsets.only(top: 2, bottom: 8),
                      decoration: BoxDecoration(
                        color: const Color(0x47FFFFFF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),

                  // Шапка: кнопка закрыть + заголовок + поделиться + меню
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildGlassButton(
                        icon: Icons.keyboard_arrow_down_rounded,
                        size: 40,
                        iconSize: 26,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      const Column(
                        children: [
                          Text(
                            'СЕЙЧАС ИГРАЕТ',
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.6,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF888E99),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'AuxBass Music',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          _buildGlassButton(
                            icon: Icons.share_rounded,
                            size: 40,
                            iconSize: 18,
                            onTap: () {
                              final link = 'https://aux.ganj4craft.ru/track/${currentTrack.id}';
                              Clipboard.setData(ClipboardData(text: link));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Ссылка на трек скопирована')),
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          _buildGlassButton(
                            icon: Icons.more_vert_rounded,
                            size: 40,
                            iconSize: 20,
                            onTap: () {
                              TrackActionSheet.show(
                                context,
                                track: currentTrack,
                                audioHandler: widget.audioHandler,
                                onLikeChanged: () => setState(() {}),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Обложка с неоновым изумрудным свечением
                  Center(
                    child: Container(
                      width: coverSize,
                      height: coverSize,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: const Color(0x1FFFFFFF), width: 1),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0xB3000000),
                            blurRadius: 36,
                            offset: Offset(0, 16),
                          ),
                          BoxShadow(
                            color: Color(0x2E22E066),
                            blurRadius: 50,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: currentTrack.fullCoverUrl != null
                            ? CachedNetworkImage(
                                imageUrl: currentTrack.fullCoverUrl!,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(color: AppTheme.bg3),
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

                  // Инфо о треке (центрированное, как на сайте)
                  Column(
                    children: [
                      Text(
                        currentTrack.title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: [
                            Shadow(color: Colors.black87, blurRadius: 10, offset: Offset(0, 2)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ArtistDetailScreen(
                                      artistName: currentTrack.artist,
                                      audioHandler: widget.audioHandler,
                                    ),
                                  ),
                                );
                              },
                              child: Text(
                                currentTrack.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFFB0B0B0),
                                ),
                              ),
                            ),
                          ),
                          if (currentTrack.albumName != null && currentTrack.albumName!.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            const Text('•', style: TextStyle(color: Color(0x80B0B0B0), fontSize: 13)),
                            const SizedBox(width: 6),
                            const Icon(Icons.album_rounded, size: 14, color: Color(0x99B0B0B0)),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                currentTrack.albumName!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, color: Color(0x99B0B0B0)),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Бейдж прослушиваний
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B1D22),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0x14FFFFFF)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.headphones_rounded, size: 12, color: Color(0xFF22E066)),
                            const SizedBox(width: 5),
                            Text(
                              '${currentTrack.formattedPlayCount} прослушиваний',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFB0B0B0)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Прогресс бар
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
                              activeTrackColor: const Color(0xFF22E066),
                              inactiveTrackColor: const Color(0x1FFFFFFF),
                              thumbColor: Colors.white,
                              trackHeight: 3.5,
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
                                Text(_formatTime(position), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF7E8490))),
                                Text(_formatTime(total), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF7E8490))),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  // Главные кнопки управления (круглые неоморфные)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildNeumorphicButton(
                        size: 44,
                        isActive: widget.audioHandler.isShuffle,
                        icon: Icons.shuffle_rounded,
                        iconSize: 20,
                        onTap: () {
                          widget.audioHandler.toggleShuffle();
                          setState(() {});
                        },
                      ),
                      _buildNeumorphicButton(
                        size: 48,
                        icon: Icons.skip_previous_rounded,
                        iconSize: 26,
                        onTap: () => widget.audioHandler.skipToPrevious(),
                      ),
                      // Большая сочная изумрудная кнопка Play
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
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF22E066), Color(0xFF159B43)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                border: Border.all(color: const Color(0x59FFFFFF), width: 1),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x99000000),
                                    blurRadius: 18,
                                    offset: Offset(4, 6),
                                  ),
                                  BoxShadow(
                                    color: Color(0x6622E066),
                                    blurRadius: 24,
                                    spreadRadius: 1,
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
                                          valueColor: AlwaysStoppedAnimation(Colors.black),
                                        ),
                                      ),
                                    )
                                  : Icon(
                                      isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                      size: 38,
                                      color: Colors.black,
                                    ),
                            ),
                          );
                        },
                      ),
                      _buildNeumorphicButton(
                        size: 48,
                        icon: Icons.skip_next_rounded,
                        iconSize: 26,
                        onTap: () => widget.audioHandler.skipToNext(),
                      ),
                      _buildNeumorphicButton(
                        size: 44,
                        isActive: widget.audioHandler.loopMode != LoopMode.off,
                        icon: widget.audioHandler.loopMode == LoopMode.one
                            ? Icons.repeat_one_rounded
                            : Icons.repeat_rounded,
                        iconSize: 20,
                        onTap: () {
                          widget.audioHandler.toggleLoopMode();
                          setState(() {});
                        },
                      ),
                    ],
                  ),

                  // Нижняя панель действий (Bottom Controls): Like, Громкость, Lyrics, Очередь
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      children: [
                        // Неоморфная кнопка Лайка (розовое свечение при активности)
                        GestureDetector(
                          onTap: _isLikeLoading ? null : () => _toggleLike(currentTrack),
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: currentTrack.isLiked
                                  ? const LinearGradient(
                                      colors: [
                                        Color(0x3DFF4B7B),
                                        Color(0x59000000),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                              color: currentTrack.isLiked ? null : const Color(0x14FFFFFF),
                              border: Border.all(
                                color: currentTrack.isLiked
                                    ? const Color(0x88FF4B7B)
                                    : const Color(0x1FFFFFFF),
                              ),
                              boxShadow: [
                                const BoxShadow(
                                  color: Color(0x66000000),
                                  blurRadius: 6,
                                  offset: Offset(2, 3),
                                ),
                                if (currentTrack.isLiked)
                                  const BoxShadow(
                                    color: Color(0x66FF4B7B),
                                    blurRadius: 14,
                                  ),
                              ],
                            ),
                            child: Center(
                              child: _isLikeLoading
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF4B7B)),
                                    )
                                  : Icon(
                                      currentTrack.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                      size: 20,
                                      color: currentTrack.isLiked ? const Color(0xFFFF4B7B) : const Color(0xFF888E99),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Встроенный слайдер громкости
                        Expanded(
                          child: StreamBuilder<double>(
                            stream: widget.audioHandler.player.volumeStream,
                            builder: (context, snapshot) {
                              final volume = snapshot.data ?? widget.audioHandler.player.volume;
                              return Row(
                                children: [
                                  Icon(
                                    volume == 0
                                        ? Icons.volume_off_rounded
                                        : volume < 0.5
                                            ? Icons.volume_down_rounded
                                            : Icons.volume_up_rounded,
                                    size: 18,
                                    color: const Color(0xFF7E8490),
                                  ),
                                  Expanded(
                                    child: SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        activeTrackColor: const Color(0xB3FFFFFF),
                                        inactiveTrackColor: const Color(0x1FFFFFFF),
                                        thumbColor: Colors.white,
                                        trackHeight: 3,
                                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.5),
                                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                                      ),
                                      child: Slider(
                                        value: volume.clamp(0.0, 1.0),
                                        onChanged: (val) => widget.audioHandler.player.setVolume(val),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Кнопка Текста песни (Lyrics)
                        _buildGlassButton(
                          icon: Icons.lyrics_rounded,
                          size: 42,
                          iconSize: 20,
                          iconColor: const Color(0xFF888E99),
                          onTap: () => _showLyricsSheet(context, currentTrack),
                        ),
                        const SizedBox(width: 8),

                        // Кнопка Очереди (Queue)
                        _buildGlassButton(
                          icon: Icons.queue_music_rounded,
                          size: 42,
                          iconSize: 20,
                          iconColor: const Color(0xFF888E99),
                          onTap: () => _showQueueSheet(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ================= 2. СТАНДАРТНЫЙ ПЛЕЕР (MATERIAL YOU) =================
  Widget _buildNativePlayer(Track currentTrack) {
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
          IconButton(
            icon: const Icon(Icons.more_vert_rounded, size: 26, color: AppTheme.textPrimary),
            onPressed: () {
              TrackActionSheet.show(
                context,
                track: currentTrack,
                audioHandler: widget.audioHandler,
                onLikeChanged: () => setState(() {}),
              );
            },
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
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
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Большая обложка
                Center(
                  child: AspectRatio(
                    aspectRatio: 1,
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
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  currentTrack.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.headphones_rounded, size: 14, color: AppTheme.textMuted),
                              const SizedBox(width: 4),
                              Text(
                                currentTrack.formattedPlayCount,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textMuted,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: _isLikeLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
                            )
                          : Icon(
                              currentTrack.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              color: currentTrack.isLiked ? AppTheme.accent : AppTheme.textSecondary,
                              size: 28,
                            ),
                      onPressed: _isLikeLoading ? null : () => _toggleLike(currentTrack),
                    ),
                  ],
                ),

                // Полоса прогресса
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
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded, color: AppTheme.textPrimary, size: 38),
                      onPressed: () => widget.audioHandler.skipToPrevious(),
                    ),
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
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded, color: AppTheme.textPrimary, size: 38),
                      onPressed: () => widget.audioHandler.skipToNext(),
                    ),
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
        ),
      ),
    );
  }
}
