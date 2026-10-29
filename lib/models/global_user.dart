class GlobalUser {
  final int id;
  final String? username;
  final String displayName;
  final int uploadCount;
  final String? avatarUrl;

  GlobalUser({
    required this.id,
    this.username,
    required this.displayName,
    required this.uploadCount,
    this.avatarUrl,
  });

  String? get fullAvatarUrl {
    if (avatarUrl != null && avatarUrl!.trim().isNotEmpty) {
      final s = avatarUrl!.trim();
      if (s != 'null' && s != 'undefined') {
        if (s.startsWith('http://') || s.startsWith('https://')) {
          if (s.contains('t.me/i/userpic')) {
            final regMatch = RegExp(r'/userpic/\d+/([^./?]+)').firstMatch(s);
            final uName = (username != null && username!.trim().isNotEmpty)
                ? username!.replaceFirst('@', '').trim()
                : regMatch?.group(1);
            if (uName != null && uName.isNotEmpty) {
              return 'https://unavatar.io/telegram/$uName';
            }
          }
          return s;
        }
        if (s.startsWith('/')) return 'https://aux.ganj4craft.ru$s';
        return 'https://aux.ganj4craft.ru/$s';
      }
    }
    if (username != null && username!.isNotEmpty) {
      final clean = username!.replaceFirst('@', '').trim();
      if (clean.isNotEmpty) {
        return 'https://unavatar.io/telegram/$clean';
      }
    }
    return null;
  }

  factory GlobalUser.fromJson(Map<String, dynamic> json) {
    return GlobalUser(
      id: json['id'] as int,
      username: json['username'] as String?,
      displayName: json['display_name'] as String? ?? json['username'] ?? 'User #${json['id']}',
      uploadCount: (json['upload_count'] as num?)?.toInt() ?? 0,
      avatarUrl: (json['avatar_url'] ?? json['avatar'] ?? json['photo_url']) as String?,
    );
  }
}
