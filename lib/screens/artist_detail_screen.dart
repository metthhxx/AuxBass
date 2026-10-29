import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/artist.dart';
import '../models/track.dart';
import '../services/api_service.dart';
import '../services/audio_player_handler.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/track_tile.dart';
import 'album_detail_screen.dart';

class ArtistDetailScreen extends StatefulWidget {
  final String artistName;
  final Artist? initialArtist;
  final AudioPlayerHandler audioHandler;

  const ArtistDetailScreen({
    super.key,
    required this.artistName,
    this.initialArtist,
    required this.audioHandler,
  });

  @override
  State<ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends State<ArtistDetailScreen> {
  final ApiService _apiService = ApiService();
  Artist? _artist;
  List<Track> _tracks = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadArtist();
  }

  Future<void> _loadArtist() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final infoFuture = _apiService.getArtistInfo(widget.artistName);
      final tracksFuture = _apiService.getArtistTracks(widget.artistName);

      final results = await Future.wait([infoFuture, tracksFuture]);
      final artistInfo = results[0] as Artist;
      final tracksList = results[1] as List<Track>;

      if (mounted) {
        setState(() {
          _artist = artistInfo;
          _tracks = tracksList;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Не удалось загрузить данные исполнителя';
          _isLoading = false;
        });
      }
    }
  }

  void _playAll({bool shuffle = false}) {
    if (_tracks.isEmpty) return;
    final list = List<Track>.from(_tracks);
    if (shuffle) {
      list.shuffle();
    }
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
          widget.artistName,
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
                            const Icon(Icons.person_outline_rounded, size: 60, color: AppTheme.textMuted),
                            const SizedBox(height: 12),
                            Text(_error!, style: const TextStyle(color: AppTheme.textSecondary)),
                            const SizedBox(height: 16),
                            FilledButton.tonal(onPressed: _loadArtist, child: const Text('Повторить')),
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
    final artist = _artist!;
    final avatar = artist.imageUrl ?? (_tracks.isNotEmpty ? _tracks.first.fullCoverUrl : null);

    return CustomScrollView(
      slivers: [
        // Шапка исполнителя
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              children: [
                // Круглый аватар
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(102),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: avatar != null
                        ? CachedNetworkImage(
                            imageUrl: avatar,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: AppTheme.bg2,
                              child: const Icon(Icons.person_rounded, size: 70, color: AppTheme.textMuted),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: AppTheme.bg2,
                              child: const Icon(Icons.person_rounded, size: 70, color: AppTheme.textMuted),
                            ),
                          )
                        : Container(
                            color: AppTheme.bg2,
                            child: const Icon(Icons.person_rounded, size: 70, color: AppTheme.textMuted),
                          ),
                  ),
                ),
                const SizedBox(height: 16),

                // Имя
                Text(
                  artist.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),

                // Статистика
                Text(
                  [
                    '${_tracks.length} ${_tracks.length == 1 ? "трек" : (_tracks.length > 1 && _tracks.length < 5 ? "трека" : "треков")}',
                    if (artist.albums.isNotEmpty)
                      '${artist.albums.length} ${artist.albums.length == 1 ? "альбом" : (artist.albums.length > 1 && artist.albums.length < 5 ? "альбома" : "альбомов")}',
                  ].join(' • '),
                  style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 18),

                // Кнопки Слушать и Шафл
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _tracks.isEmpty ? null : () => _playAll(shuffle: false),
                      icon: const Icon(Icons.play_arrow_rounded, size: 24),
                      label: const Text('Слушать всё', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.bg4),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _tracks.isEmpty ? null : () => _playAll(shuffle: true),
                      icon: const Icon(Icons.shuffle_rounded, size: 20, color: AppTheme.textPrimary),
                      label: const Text('Шафл', style: TextStyle(color: AppTheme.textPrimary)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Секция Альбомов (если есть)
        if (artist.albums.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Text(
                    'Альбомы и релизы',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.bg3,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${artist.albums.length}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.accentLight, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 190,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: artist.albums.length,
                itemBuilder: (context, idx) {
                  final album = artist.albums[idx];
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AlbumDetailScreen(
                            albumId: album.id,
                            initialAlbum: album,
                            audioHandler: widget.audioHandler,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      width: 130,
                      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: SizedBox(
                              width: 130,
                              height: 130,
                              child: album.coverUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: album.coverUrl!,
                                      fit: BoxFit.cover,
                                      placeholder: (_, __) => Container(color: AppTheme.bg2),
                                      errorWidget: (_, __, ___) => Container(
                                        color: AppTheme.bg2,
                                        child: const Icon(Icons.album_rounded, color: AppTheme.textMuted),
                                      ),
                                    )
                                  : Container(
                                      color: AppTheme.bg2,
                                      child: const Icon(Icons.album_rounded, color: AppTheme.textMuted),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            album.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Text(
                            album.year != null && album.year! > 0 ? '${album.year}' : '${album.trackCount} треков',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],

        // Секция треков
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              'Треки исполнителя (${_tracks.length})',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ),

        if (_tracks.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Center(
                child: Text('Нет доступных треков', style: TextStyle(color: AppTheme.textMuted)),
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
      ],
    );
  }
}
