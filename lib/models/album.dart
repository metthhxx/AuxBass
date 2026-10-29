import 'track.dart';

class Album {
  final dynamic id; // может быть int или String (например slug или hash)
  final String title;
  final String artist;
  final String? coverUrl;
  final int? year;
  final int trackCount;
  final int totalTracks;
  final List<Track> tracks;

  Album({
    required this.id,
    required this.title,
    required this.artist,
    this.coverUrl,
    this.year,
    this.trackCount = 0,
    this.totalTracks = 0,
    this.tracks = const [],
  });

  factory Album.fromJson(Map<String, dynamic> json) {
    final rawTracks = json['tracks'] ?? json['full_tracklist'];
    final tracksList = <Track>[];
    if (rawTracks is List) {
      for (final item in rawTracks) {
        if (item is Map<String, dynamic>) {
          if (item['track'] is Map<String, dynamic>) {
            tracksList.add(Track.fromJson(item['track'] as Map<String, dynamic>));
          } else {
            tracksList.add(Track.fromJson(item));
          }
        }
      }
    }

    final tCount = (json['track_count'] as num?)?.toInt() ?? tracksList.length;
    final totCount = (json['total_tracks'] as num?)?.toInt() ?? tCount;

    return Album(
      id: json['id'] ?? json['album_id'] ?? 0,
      title: json['title'] as String? ?? json['name'] as String? ?? 'Без названия',
      artist: json['artist'] as String? ?? json['artist_name'] as String? ?? 'Неизвестный исполнитель',
      coverUrl: json['cover_url'] as String? ?? json['cover'] as String?,
      year: (json['year'] as num?)?.toInt() ?? (json['release_year'] as num?)?.toInt(),
      trackCount: tCount,
      totalTracks: totCount,
      tracks: tracksList,
    );
  }
}
