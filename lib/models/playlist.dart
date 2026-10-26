class Playlist {
  final int id;
  final String name;
  final String? coverUrl;
  final int trackCount;
  final String? description;

  Playlist({
    required this.id,
    required this.name,
    this.coverUrl,
    this.trackCount = 0,
    this.description,
  });

  String? get fullCoverUrl {
    if (coverUrl == null || coverUrl!.isEmpty) return null;
    if (coverUrl!.startsWith('http://') || coverUrl!.startsWith('https://')) {
      return coverUrl;
    }
    return 'https://aux.ganj4craft.ru$coverUrl';
  }

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'Без названия',
      coverUrl: json['cover_url'] as String?,
      trackCount: (json['track_count'] as num?)?.toInt() ?? 0,
      description: json['description'] as String?,
    );
  }
}
