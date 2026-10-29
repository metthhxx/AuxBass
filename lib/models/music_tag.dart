class MusicTag {
  final String name;
  final int count;

  MusicTag({
    required this.name,
    this.count = 0,
  });

  factory MusicTag.fromJson(dynamic json) {
    if (json is String) {
      return MusicTag(name: json);
    }
    if (json is Map<String, dynamic>) {
      return MusicTag(
        name: json['name'] as String? ?? json['tag'] as String? ?? '',
        count: (json['count'] as num?)?.toInt() ?? (json['track_count'] as num?)?.toInt() ?? 0,
      );
    }
    return MusicTag(name: json.toString());
  }
}
