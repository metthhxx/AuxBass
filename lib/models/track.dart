class Track {
  final int id;
  final String title;
  final String artist;
  final int duration;
  final String? coverUrl;
  final String? albumName;
  final String? fileName;
  bool isLiked;

  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    this.coverUrl,
    this.albumName,
    this.fileName,
    this.isLiked = false,
  });

  /// Полная ссылка на обложку с учетом домена сервера
  String? get fullCoverUrl {
    if (coverUrl == null || coverUrl!.isEmpty) return null;
    if (coverUrl!.startsWith('http://') || coverUrl!.startsWith('https://')) {
      return coverUrl;
    }
    return 'https://aux.ganj4craft.ru$coverUrl';
  }

  /// Форматированная длительность (мм:сс)
  String get formattedDuration {
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  factory Track.fromJson(Map<String, dynamic> json) {
    String? cover = json['cover_url'] as String?;
    String? album = json['album_name'] as String?;

    if (json['album'] is Map) {
      final albumMap = json['album'] as Map<String, dynamic>;
      album ??= albumMap['name'] as String?;
      cover ??= albumMap['cover_url'] as String?;
    }

    return Track(
      id: json['id'] as int,
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? (json['title'] as String).trim()
          : (json['file_name'] as String? ?? 'Без названия'),
      artist: (json['artist'] as String?)?.trim().isNotEmpty == true
          ? (json['artist'] as String).trim()
          : 'Неизвестный исполнитель',
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      coverUrl: cover,
      albumName: album,
      fileName: json['file_name'] as String?,
      isLiked: json['is_liked'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'duration': duration,
      'cover_url': coverUrl,
      'album_name': albumName,
      'file_name': fileName,
      'is_liked': isLiked,
    };
  }
}
