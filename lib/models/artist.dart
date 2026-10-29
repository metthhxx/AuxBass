import 'album.dart';
import 'track.dart';

class Artist {
  final String name;
  final String? imageUrl;
  final int trackCount;
  final int albumCount;
  final List<Album> albums;
  final List<Track> tracks;

  Artist({
    required this.name,
    this.imageUrl,
    this.trackCount = 0,
    this.albumCount = 0,
    this.albums = const [],
    this.tracks = const [],
  });

  factory Artist.fromJson(Map<String, dynamic> json) {
    final rawAlbums = json['albums'];
    final albumsList = <Album>[];
    if (rawAlbums is List) {
      for (final item in rawAlbums) {
        if (item is Map<String, dynamic>) {
          albumsList.add(Album.fromJson(item));
        }
      }
    }

    final rawTracks = json['tracks'];
    final tracksList = <Track>[];
    if (rawTracks is List) {
      for (final item in rawTracks) {
        if (item is Map<String, dynamic>) {
          tracksList.add(Track.fromJson(item));
        }
      }
    }

    return Artist(
      name: json['name'] as String? ?? json['artist'] as String? ?? 'Неизвестный исполнитель',
      imageUrl: json['image_url'] as String? ?? json['image'] as String? ?? json['avatar_url'] as String?,
      trackCount: (json['track_count'] as num?)?.toInt() ?? tracksList.length,
      albumCount: (json['album_count'] as num?)?.toInt() ?? albumsList.length,
      albums: albumsList,
      tracks: tracksList,
    );
  }
}
