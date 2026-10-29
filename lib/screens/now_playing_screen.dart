import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:palette_generator/palette_generator.dart';
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

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  double? _dragPosition;
  bool _isLikeLoading = false;
  late final AnimationController _spinController;

  // Динамическая палитра обложки
  Color? _dominantColor;
  String? _lastCoverUrl;

  // Интерактивный скретч винила
  bool _isScratching = false;
  double _scratchAngle = 0.0;
  double _lastTouchAngle = 0.0;
  bool _wasPlayingBeforeScratch = false;
  double _hapticAccumulator = 0.0;

  String _formatTime(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    // Вращение винила ~33 1/3 RPM (один полный оборот за ~1.8 сек)
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );
    if (widget.audioHandler.player.playing) {
      _spinController.repeat();
    }

    PlayerSettingsService.dynamicThemeNotifier.addListener(_onDynamicThemeChanged);
    final initialTrack = widget.audioHandler.currentTrack;
    if (initialTrack != null) {
      _updateCoverPalette(initialTrack);
    }
  }

  @override
  void dispose() {
    PlayerSettingsService.dynamicThemeNotifier.removeListener(_onDynamicThemeChanged);
    _spinController.dispose();
    super.dispose();
  }

  void _onDynamicThemeChanged() {
    final track = widget.audioHandler.currentTrack;
    if (track != null) {
      _lastCoverUrl = null;
      _updateCoverPalette(track);
    }
  }

  Future<void> _updateCoverPalette(Track track) async {
    if (!PlayerSettingsService.dynamicThemeNotifier.value) {
      if (_dominantColor != null) {
        setState(() => _dominantColor = null);
      }
      return;
    }
    final url = track.fullCoverUrl;
    if (url == null) {
      if (_dominantColor != null) {
        setState(() => _dominantColor = null);
      }
      return;
    }
    if (url == _lastCoverUrl) return;
    _lastCoverUrl = url;

    try {
      final palette = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(url),
        maximumColorCount: 16,
      );
      final color = palette.vibrantColor?.color ??
          palette.dominantColor?.color ??
          palette.lightVibrantColor?.color;
      if (mounted && color != null) {
        setState(() {
          _dominantColor = color;
        });
      }
    } catch (_) {}
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

  void _showQueueSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0C0E14),
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                            'ОЧЕРЕДЬ (${queue.length} ТРЕКОВ)',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: Color(0xFF00FF66),
                              fontFamily: 'monospace',
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              widget.audioHandler.toggleShuffle();
                              setState(() {});
                            },
                            child: Text(
                              widget.audioHandler.isShuffle ? 'Шафл вкл' : 'Перемешать',
                              style: const TextStyle(color: Color(0xFF00FF66), fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Color(0xFF1E222D), height: 1),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: queue.length,
                        itemBuilder: (context, i) {
                          final tr = queue[i];
                          final isCur = tr.id == current?.id;
                          return ListTile(
                            selected: isCur,
                            selectedTileColor: const Color(0x1400FF66),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
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
                                color: isCur ? const Color(0xFF00FF66) : Colors.white,
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
                                ? const Icon(Icons.graphic_eq_rounded, color: Color(0xFF00FF66), size: 20)
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

            _updateCoverPalette(currentTrack);

            if (style == PlayerStyle.djx) {
              return _buildDjxTurntablePlayer(currentTrack);
            } else {
              return _buildNativePlayer(currentTrack);
            }
          },
        );
      },
    );
  }

  // ================= 1. DJX-4000 ВИНИЛОВЫЙ DJ-ПУЛЬТ (КАК НА САЙТЕ / СКРИНШОТЕ) =================
  Widget _buildDjxTurntablePlayer(Track currentTrack) {
    return StreamBuilder<PlayerState>(
      stream: widget.audioHandler.player.playerStateStream,
      builder: (context, playerSnapshot) {
        final state = playerSnapshot.data;
        final isPlaying = state?.playing ?? false;
        final isBuffering = state?.processingState == ProcessingState.buffering ||
            state?.processingState == ProcessingState.loading;

        // Контроль анимации вращения винила
        if (isPlaying) {
          if (!_spinController.isAnimating) {
            _spinController.repeat();
          }
        } else {
          if (_spinController.isAnimating) {
            _spinController.stop();
          }
        }

        return Scaffold(
          backgroundColor: const Color(0xFF090A0E),
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
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.6),
                  radius: 1.2,
                  colors: [
                    _dominantColor != null
                        ? Color.lerp(const Color(0xFF131722), _dominantColor!, 0.35)!
                        : const Color(0xFF131722),
                    _dominantColor != null
                        ? Color.lerp(const Color(0xFF0C0E14), _dominantColor!, 0.18)!
                        : const Color(0xFF0C0E14),
                    const Color(0xFF07080B),
                  ],
                ),
              ),
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final platterSize = (constraints.maxHeight * 0.35).clamp(180.0, 270.0);
                    return SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // 1. Верхняя панель бейджей: [ AUX-BASS DJX-4000 ] и [ ● STANDBY / ON AIR ]
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF888E99), size: 28),
                                    onPressed: () => Navigator.of(context).pop(),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    tooltip: 'Свернуть',
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0D0F14),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFF1E222B)),
                                      boxShadow: const [
                                        BoxShadow(color: Colors.black45, blurRadius: 4),
                                      ],
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'AUX-BASS',
                                          style: TextStyle(
                                            color: Color(0xFF00FF66),
                                            fontWeight: FontWeight.w900,
                                            fontSize: 11.5,
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'DJX-4000',
                                          style: TextStyle(
                                            color: Color(0xFF888E99),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                            letterSpacing: 1.0,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Spacer(),
                                  GestureDetector(
                                    onTap: () => Navigator.of(context).pop(),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0D0F14),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFF1E222B)),
                                        boxShadow: const [
                                          BoxShadow(color: Colors.black45, blurRadius: 4),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 7,
                                            height: 7,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: isPlaying ? const Color(0xFF00FF66) : const Color(0xFFE53935),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: isPlaying ? const Color(0x9900FF66) : const Color(0x99E53935),
                                                  blurRadius: 6,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            isPlaying ? 'ON AIR' : 'STANDBY',
                                            style: TextStyle(
                                              color: isPlaying ? const Color(0xFF00FF66) : const Color(0xFF9E3A3A),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 10.5,
                                              letterSpacing: 1.2,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                      // 2. Блок вертушки: RPM/DIRECT DRIVE дисплей + вращающийся винил + тонарм
                      Column(
                        children: [
                          // Мини-индикаторы скорости над пластинкой
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF080D14),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: const Color(0xFF142233)),
                                ),
                                child: const Column(
                                  children: [
                                    Text('33 ⅓', style: TextStyle(color: Color(0xFF00FF66), fontSize: 9.5, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                                    Text('RPM', style: TextStyle(color: Color(0xFF00FF66), fontSize: 8, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF080D14),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: const Color(0xFF142233)),
                                ),
                                child: const Column(
                                  children: [
                                    Text('DIRECT', style: TextStyle(color: Color(0xFF888E99), fontSize: 8.5, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                                    Text('DRIVE', style: TextStyle(color: Color(0xFF888E99), fontSize: 8.5, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Виниловая вертушка с тонармом
                          _buildTurntablePlatter(currentTrack, isPlaying, platterSize),
                        ],
                      ),

                      // 3. Экран трека в стиле ретро-консоли (CRT Scanline Rack Display)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF080D14),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _dominantColor != null
                                ? Color.lerp(const Color(0xFF142233), _dominantColor!, 0.4)!
                                : const Color(0xFF142233),
                            width: 1.5,
                          ),
                          boxShadow: [
                            const BoxShadow(color: Colors.black87, blurRadius: 10, offset: Offset(0, 3)),
                            BoxShadow(
                              color: _dominantColor != null
                                  ? _dominantColor!.withAlpha(45)
                                  : const Color(0x1F4DC3FF),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _CrtScanlinesPainter(),
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentTrack.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                    shadows: [
                                      Shadow(color: Color(0x994DC3FF), blurRadius: 8),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Text(
                                      'ARTIST: ',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF4DC3FF),
                                        letterSpacing: 1.0,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    Expanded(
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
                                          currentTrack.artist.toUpperCase(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF4DC3FF),
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (currentTrack.playCount > 0)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.headphones_rounded, size: 12, color: Color(0xFF00FF66)),
                                          const SizedBox(width: 3),
                                          Text(
                                            currentTrack.formattedPlayCount,
                                            style: const TextStyle(color: Color(0xFF00FF66), fontSize: 11, fontFamily: 'monospace'),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // 4. Полоса прогресса со светодиодными таймингами
                      StreamBuilder<Duration>(
                        stream: widget.audioHandler.player.positionStream,
                        builder: (context, snapshot) {
                          final position = snapshot.data ?? Duration.zero;
                          final total = widget.audioHandler.player.duration ?? Duration(seconds: currentTrack.duration);

                          final maxVal = total.inMilliseconds.toDouble();
                          final currentVal = _dragPosition ?? position.inMilliseconds.toDouble().clamp(0.0, maxVal);

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0A0C10),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF161820)),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  _formatTime(position),
                                  style: const TextStyle(
                                    color: Color(0xFF00FF66),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                    fontFamily: 'monospace',
                                    letterSpacing: 1.0,
                                    shadows: [
                                      Shadow(color: Color(0x6600FF66), blurRadius: 6),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      activeTrackColor: const Color(0xFF00FF66),
                                      inactiveTrackColor: const Color(0xFF1E222D),
                                      thumbColor: Colors.white,
                                      trackHeight: 3.5,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
                                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                                    ),
                                    child: Slider(
                                      value: currentVal > maxVal ? maxVal : currentVal,
                                      max: maxVal > 0 ? maxVal : 1.0,
                                      onChanged: (val) => setState(() => _dragPosition = val),
                                      onChangeEnd: (val) {
                                        widget.audioHandler.seek(Duration(milliseconds: val.toInt()));
                                        setState(() => _dragPosition = null);
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _formatTime(total),
                                  style: const TextStyle(
                                    color: Color(0xFF888E99),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    fontFamily: 'monospace',
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      // 5. Панель DJ-кнопок (SYNC, CUE, PLAY, NEXT, LOOP)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0C0E14),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF1A1E28)),
                          boxShadow: const [
                            BoxShadow(color: Colors.black87, blurRadius: 10, offset: Offset(0, 4)),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildDjSquarePad(
                              icon: Icons.shuffle_rounded,
                              label: 'SYNC',
                              isActive: widget.audioHandler.isShuffle,
                              onTap: () {
                                widget.audioHandler.toggleShuffle();
                                setState(() {});
                              },
                            ),
                            _buildDjSquarePad(
                              icon: Icons.skip_previous_rounded,
                              label: 'CUE',
                              onTap: () => widget.audioHandler.skipToPrevious(),
                            ),
                            _buildDjCenterPlayButton(isPlaying, isBuffering),
                            _buildDjSquarePad(
                              icon: Icons.skip_next_rounded,
                              label: 'NEXT',
                              onTap: () => widget.audioHandler.skipToNext(),
                            ),
                            _buildDjSquarePad(
                              icon: widget.audioHandler.loopMode == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                              label: 'LOOP',
                              isActive: widget.audioHandler.loopMode != LoopMode.off,
                              onTap: () {
                                widget.audioHandler.toggleLoopMode();
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                      ),

                      // 6. Нижний фейдер громкости с дБ шкалой + Like + Queue
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0C0E14),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF1A1E28)),
                          boxShadow: const [
                            BoxShadow(color: Colors.black87, blurRadius: 8, offset: Offset(0, 3)),
                          ],
                        ),
                        child: Row(
                          children: [
                            StreamBuilder<double>(
                              stream: widget.audioHandler.player.volumeStream,
                              builder: (context, snapshot) {
                                final volume = snapshot.data ?? widget.audioHandler.player.volume;
                                return Icon(
                                  volume == 0
                                      ? Icons.volume_off_rounded
                                      : volume < 0.5
                                          ? Icons.volume_down_rounded
                                          : Icons.volume_up_rounded,
                                  size: 18,
                                  color: const Color(0xFF888E99),
                                );
                              },
                            ),
                            const SizedBox(width: 8),

                            // Fader track with ticks
                            Expanded(
                              child: StreamBuilder<double>(
                                stream: widget.audioHandler.player.volumeStream,
                                builder: (context, snapshot) {
                                  final volume = (snapshot.data ?? widget.audioHandler.player.volume).clamp(0.0, 1.0);
                                  return Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('-∞', style: TextStyle(color: Color(0xFF5A6273), fontSize: 8.5, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                                          Text('-12', style: TextStyle(color: Color(0xFF5A6273), fontSize: 8.5, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                                          Text('0', style: TextStyle(color: Color(0xFF5A6273), fontSize: 8.5, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                                          Text('+6', style: TextStyle(color: Color(0xFF5A6273), fontSize: 8.5, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          activeTrackColor: const Color(0xFF00FF66),
                                          inactiveTrackColor: const Color(0xFF1E222D),
                                          thumbColor: const Color(0xFF444A57),
                                          trackHeight: 4,
                                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                                        ),
                                        child: Slider(
                                          value: volume,
                                          onChanged: (val) => widget.audioHandler.player.setVolume(val),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),

                            // 100% indicator
                            StreamBuilder<double>(
                              stream: widget.audioHandler.player.volumeStream,
                              builder: (context, snapshot) {
                                final volume = (snapshot.data ?? widget.audioHandler.player.volume).clamp(0.0, 1.0);
                                final pct = (volume * 100).toInt();
                                return Container(
                                  margin: const EdgeInsets.only(left: 4, right: 8),
                                  child: Text(
                                    '$pct%',
                                    style: const TextStyle(
                                      color: Color(0xFF00FF66),
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                );
                              },
                            ),

                            // Like button
                            GestureDetector(
                              onTap: _isLikeLoading ? null : () => _toggleLike(currentTrack),
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF12141A),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: currentTrack.isLiked ? const Color(0xFFFF4B7B) : const Color(0xFF20242E),
                                  ),
                                  boxShadow: [
                                    if (currentTrack.isLiked)
                                      const BoxShadow(color: Color(0x66FF4B7B), blurRadius: 10),
                                  ],
                                ),
                                child: Center(
                                  child: _isLikeLoading
                                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF4B7B)))
                                      : Icon(
                                          currentTrack.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                          size: 18,
                                          color: currentTrack.isLiked ? const Color(0xFFFF4B7B) : const Color(0xFF888E99),
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),

                            // Queue button
                            GestureDetector(
                              onTap: () => _showQueueSheet(context),
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF12141A),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF20242E)),
                                ),
                                child: const Center(
                                  child: Icon(Icons.menu_rounded, size: 18, color: Color(0xFF888E99)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  ),
);
      },
    );
  }

  // --- Компоненты вертушки DJX-4000 ---

  Widget _buildTurntablePlatter(Track currentTrack, bool isPlaying, double platterSize) {
    final discSize = platterSize * 0.88;
    final labelSize = discSize * 0.44;

    return SizedBox(
      width: platterSize,
      height: platterSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Внешнее основание вертушки
          Container(
            width: platterSize,
            height: platterSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0B0C0F),
              boxShadow: [
                const BoxShadow(color: Colors.black87, blurRadius: 24, offset: Offset(0, 8)),
                BoxShadow(
                  color: _dominantColor != null ? _dominantColor!.withAlpha(35) : const Color(0x1F00FF66),
                  blurRadius: 36,
                ),
              ],
              border: Border.all(color: const Color(0xFF1E222D), width: 2),
            ),
          ),

          // Вращающаяся пластинка с поддержкой интерактивного скретча
          ValueListenableBuilder<bool>(
            valueListenable: PlayerSettingsService.scratchEnabledNotifier,
            builder: (context, scratchEnabled, _) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: !scratchEnabled ? null : (details) {
                  final center = Offset(discSize / 2, discSize / 2);
                  final offset = details.localPosition - center;
                  _lastTouchAngle = atan2(offset.dy, offset.dx);
                  _isScratching = true;
                  _wasPlayingBeforeScratch = widget.audioHandler.player.playing;
                  _scratchAngle = _spinController.value * 2 * pi;
                  _hapticAccumulator = 0.0;
                  if (_wasPlayingBeforeScratch) {
                    widget.audioHandler.player.pause();
                  }
                  _spinController.stop();
                  HapticFeedback.selectionClick();
                  setState(() {});
                },
                onPanUpdate: !scratchEnabled ? null : (details) {
                  if (!_isScratching) return;
                  final center = Offset(discSize / 2, discSize / 2);
                  final offset = details.localPosition - center;
                  final currentAngle = atan2(offset.dy, offset.dx);
                  var delta = currentAngle - _lastTouchAngle;
                  if (delta > pi) delta -= 2 * pi;
                  if (delta < -pi) delta += 2 * pi;
                  _lastTouchAngle = currentAngle;
                  _scratchAngle += delta;

                  _hapticAccumulator += delta.abs();
                  if (_hapticAccumulator > 0.35) {
                    _hapticAccumulator = 0.0;
                    HapticFeedback.selectionClick();
                  }

                  // 33 1/3 RPM = 1 оборот за 1.8с (1800мс)
                  final scrubMs = ((delta / (2 * pi)) * 1800).toInt();
                  final currentPos = widget.audioHandler.player.position;
                  final total = widget.audioHandler.player.duration ?? Duration(seconds: currentTrack.duration);
                  final targetMs = (currentPos.inMilliseconds + scrubMs).clamp(0, total.inMilliseconds);
                  widget.audioHandler.seek(Duration(milliseconds: targetMs));

                  setState(() {});
                },
                onPanEnd: !scratchEnabled ? null : (_) {
                  if (!_isScratching) return;
                  _isScratching = false;
                  final turns = (_scratchAngle / (2 * pi)) % 1.0;
                  _spinController.value = turns < 0 ? turns + 1.0 : turns;
                  if (_wasPlayingBeforeScratch) {
                    widget.audioHandler.player.play();
                    _spinController.repeat();
                  }
                  setState(() {});
                },
                onPanCancel: !scratchEnabled ? null : () {
                  if (!_isScratching) return;
                  _isScratching = false;
                  final turns = (_scratchAngle / (2 * pi)) % 1.0;
                  _spinController.value = turns < 0 ? turns + 1.0 : turns;
                  if (_wasPlayingBeforeScratch) {
                    widget.audioHandler.player.play();
                    _spinController.repeat();
                  }
                  setState(() {});
                },
                child: AnimatedBuilder(
                  animation: _spinController,
                  builder: (context, child) {
                    final angle = _isScratching ? _scratchAngle : (_spinController.value * 2 * pi);
                    return Transform.rotate(
                      angle: angle,
                      child: child,
                    );
                  },
                  child: Container(
                    width: discSize,
                    height: discSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [Color(0xFF252830), Color(0xFF121418), Color(0xFF0A0B0D)],
                        stops: [0.0, 0.65, 1.0],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _isScratching ? const Color(0x6600FF66) : Colors.black54,
                          blurRadius: _isScratching ? 16 : 10,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _VinylPlatterPainter(),
                          ),
                        ),

                        // Яблоко винила с обложкой
                        Container(
                          width: labelSize,
                          height: labelSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            border: Border.all(color: const Color(0xFF222222), width: 2.5),
                            boxShadow: const [
                              BoxShadow(color: Colors.black87, blurRadius: 6),
                            ],
                          ),
                          child: ClipOval(
                            child: currentTrack.fullCoverUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: currentTrack.fullCoverUrl!,
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

                        // Центральный шпиндель
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const RadialGradient(
                              colors: [Color(0xFFE9ECEF), Color(0xFF495057)],
                            ),
                            border: Border.all(color: const Color(0xFF212529), width: 1.5),
                            boxShadow: const [
                              BoxShadow(color: Colors.black54, blurRadius: 3),
                            ],
                          ),
                          child: Center(
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          // Тонарм
          _buildTonearm(isPlaying, platterSize),
        ],
      ),
    );
  }

  Widget _buildTonearm(bool isPlaying, double platterSize) {
    return Positioned(
      top: 6,
      right: 4,
      child: AnimatedRotation(
        turns: isPlaying ? 0.025 : -0.045,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        alignment: const Alignment(0.65, -0.85),
        child: SizedBox(
          width: 60,
          height: platterSize * 0.78,
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              // База тонарма
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [Color(0xFF6C757D), Color(0xFF2B303A)],
                  ),
                  border: Border.all(color: const Color(0xFF888E99), width: 1.5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 3)),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF16181F),
                    ),
                  ),
                ),
              ),

              // Шток тонарма
              Positioned(
                top: 24,
                right: 14,
                bottom: 22,
                child: Container(
                  width: 3.5,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFCED4DA), Color(0xFF495057)],
                    ),
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(1, 1)),
                    ],
                  ),
                ),
              ),

              // Игла / Картридж
              Positioned(
                bottom: 0,
                right: 6,
                child: Transform.rotate(
                  angle: 0.25,
                  child: Container(
                    width: 14,
                    height: 26,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E222B),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: const Color(0xFF6C757D), width: 1),
                      boxShadow: const [
                        BoxShadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 2)),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 4,
                        height: 10,
                        decoration: BoxDecoration(
                          color: const Color(0xFF00FF66),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDjSquarePad({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 56,
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF132219) : const Color(0xFF12141A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? const Color(0xFF00FF66) : const Color(0xFF20242E),
            width: 1.2,
          ),
          boxShadow: [
            const BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 2)),
            if (isActive)
              const BoxShadow(color: Color(0x4000FF66), blurRadius: 8),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isActive ? const Color(0xFF00FF66) : const Color(0xFFCED4DA),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
                color: isActive ? const Color(0xFF00FF66) : const Color(0xFF7E8490),
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDjCenterPlayButton(bool isPlaying, bool isBuffering) {
    return GestureDetector(
      onTap: () {
        if (isPlaying) {
          widget.audioHandler.pause();
        } else {
          widget.audioHandler.play();
        }
      },
      child: Container(
        width: 66,
        height: 66,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF0D0F14),
          border: Border.all(
            color: isPlaying ? const Color(0xFF00FF66) : const Color(0xFF3A4252),
            width: 2.2,
          ),
          boxShadow: [
            const BoxShadow(color: Colors.black87, blurRadius: 8, offset: Offset(0, 4)),
            if (isPlaying)
              const BoxShadow(color: Color(0x6600FF66), blurRadius: 18),
          ],
        ),
        child: Center(
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isPlaying
                  ? const RadialGradient(colors: [Color(0xFF00FF66), Color(0xFF0B662A)])
                  : const RadialGradient(colors: [Color(0xFF252A36), Color(0xFF14171F)]),
            ),
            child: isBuffering
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    ),
                  )
                : Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 32,
                    color: isPlaying ? Colors.black : Colors.white,
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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _dominantColor != null ? _dominantColor!.withAlpha(50) : AppTheme.bg1,
              AppTheme.bg0,
              AppTheme.bg0,
            ],
          ),
        ),
        child: GestureDetector(
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
                            activeTrackColor: _dominantColor ?? AppTheme.accent,
                            inactiveTrackColor: AppTheme.bg4,
                            thumbColor: _dominantColor != null
                                ? Color.lerp(Colors.white, _dominantColor!, 0.7)
                                : AppTheme.accentLight,
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                          ),
                          child: Slider(
                            value: currentVal > maxVal ? maxVal : currentVal,
                            max: maxVal > 0 ? maxVal : 1.0,
                            onChanged: (val) => setState(() => _dragPosition = val),
                            onChangeEnd: (val) {
                              widget.audioHandler.seek(Duration(milliseconds: val.toInt()));
                              setState(() => _dragPosition = null);
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

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.shuffle_rounded,
                        color: widget.audioHandler.isShuffle ? (_dominantColor ?? AppTheme.accent) : AppTheme.textMuted,
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
                        final btnColor = _dominantColor ?? AppTheme.accent;
                        final btnTextColor = _dominantColor != null
                            ? (_dominantColor!.computeLuminance() > 0.5 ? Colors.black : Colors.white)
                            : AppTheme.accentText;

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
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: btnColor,
                              boxShadow: [
                                BoxShadow(
                                  color: btnColor.withAlpha(120),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: isBuffering
                                ? Center(
                                    child: SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        valueColor: AlwaysStoppedAnimation(btnTextColor),
                                      ),
                                    ),
                                  )
                                : Icon(
                                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    size: 40,
                                    color: btnTextColor,
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
                        color: widget.audioHandler.loopMode != LoopMode.off ? (_dominantColor ?? AppTheme.accent) : AppTheme.textMuted,
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
    ),
  );
}
}

// --- Custom Painters для винила и CRT-экрана ---

class _VinylPlatterPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Внешние стробоскопические риски (Strobe dots)
    final strobePaint = Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    const dotCount = 52;
    for (int i = 0; i < dotCount; i++) {
      final angle = (i * 2 * pi) / dotCount;
      final x1 = center.dx + (radius - 2) * cos(angle);
      final y1 = center.dy + (radius - 2) * sin(angle);
      final x2 = center.dx + (radius - 6.5) * cos(angle);
      final y2 = center.dy + (radius - 6.5) * sin(angle);
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), strobePaint);
    }

    // Звуковые канавки винила
    final groovePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    const rings = [0.91, 0.86, 0.81, 0.76, 0.70, 0.64, 0.57, 0.51];
    for (final factor in rings) {
      groovePaint.color = const Color(0x18FFFFFF);
      canvas.drawCircle(center, radius * factor, groovePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CrtScanlinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x2E000000)
      ..strokeWidth = 1.0;

    for (double y = 0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
