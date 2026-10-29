class Track {
  final int id;
  final String title;
  final String artist;
  final int duration;
  final String? coverUrl;
  final String? albumName;
  final String? fileName;
  final int playCount;
  bool isLiked;

  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    this.coverUrl,
    this.albumName,
    this.fileName,
    this.playCount = 0,
    this.isLiked = false,
  });

  /// Форматированное количество прослушиваний (например: 1.2k, 3.4M или 42)
  String get formattedPlayCount {
    if (playCount >= 1000000) {
      final m = playCount / 1000000.0;
      return '${m.toStringAsFixed(m >= 10 ? 0 : 1)}M';
    } else if (playCount >= 1000) {
      final k = playCount / 1000.0;
      return '${k.toStringAsFixed(k >= 10 ? 0 : 1)}k';
    }
    return playCount.toString();
  }

  /// Полная ссылка на обложку с учетом проксирования внешних ресурсов
  String? get fullCoverUrl {
    if (coverUrl == null || coverUrl!.trim().isEmpty || coverUrl == 'null') return null;
    final s = coverUrl!.trim();
    if (s.startsWith('http://') || s.startsWith('https://')) {
      if (s.startsWith('https://aux.ganj4craft.ru') || s.startsWith('http://aux.ganj4craft.ru')) {
        return s;
      }
      return 'https://aux.ganj4craft.ru/api/images/proxy?url=${Uri.encodeComponent(s)}';
    }
    if (s.startsWith('/')) {
      return 'https://aux.ganj4craft.ru$s';
    }
    return 'https://aux.ganj4craft.ru/$s';
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

    final rawPlayCount = json['play_count'] ?? json['plays'] ?? json['playCount'];
    final parsedPlayCount = (rawPlayCount is num)
        ? rawPlayCount.toInt()
        : int.tryParse(rawPlayCount?.toString() ?? '') ?? 0;

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
      playCount: parsedPlayCount,
      isLiked: json['is_liked'] as bool? ?? false,
    );
  }

  Track copyWith({
    int? id,
    String? title,
    String? artist,
    int? duration,
    String? coverUrl,
    String? albumName,
    String? fileName,
    int? playCount,
    bool? isLiked,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      duration: duration ?? this.duration,
      coverUrl: coverUrl ?? this.coverUrl,
      albumName: albumName ?? this.albumName,
      fileName: fileName ?? this.fileName,
      playCount: playCount ?? this.playCount,
      isLiked: isLiked ?? this.isLiked,
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
      'play_count': playCount,
      'is_liked': isLiked,
    };
  }
}
