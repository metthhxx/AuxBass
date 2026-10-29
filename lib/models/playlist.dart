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
    if (coverUrl == null || coverUrl!.trim().isEmpty || coverUrl == 'null') return null;
    final s = coverUrl!.trim();
    if (s.startsWith('http://') || s.startsWith('https://')) {
      if (s.startsWith('https://aux.ganj4craft.ru') || s.startsWith('http://aux.ganj4craft.ru')) {
        return s;
      }
      return 'https://aux.ganj4craft.ru/api/images/proxy?url=${Uri.encodeComponent(s)}';
    }
    if (s.startsWith('/')) return 'https://aux.ganj4craft.ru$s';
    return 'https://aux.ganj4craft.ru/$s';
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
