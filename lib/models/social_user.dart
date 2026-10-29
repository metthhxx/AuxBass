class SocialUser {
  final int id;
  final String? username;
  final String? firstName;
  final String? lastName;
  final String? customNickname;
  final String? rawDisplayName;
  final String? photoUrl;
  final String? bio;
  final int followersCount;
  final int followingCount;
  final int trackCount;
  final int playlistCount;
  final int albumCount;
  bool isFollowing;
  final bool isMutual;
  final String? channelTitle;

  SocialUser({
    required this.id,
    this.username,
    this.firstName,
    this.lastName,
    this.customNickname,
    this.rawDisplayName,
    this.photoUrl,
    this.bio,
    this.followersCount = 0,
    this.followingCount = 0,
    this.trackCount = 0,
    this.playlistCount = 0,
    this.albumCount = 0,
    this.isFollowing = false,
    this.isMutual = false,
    this.channelTitle,
  });

  String get displayName {
    if (customNickname != null && customNickname!.trim().isNotEmpty) {
      return customNickname!.trim();
    }
    if (rawDisplayName != null &&
        rawDisplayName!.trim().isNotEmpty &&
        !rawDisplayName!.trim().toLowerCase().startsWith('user #') &&
        !rawDisplayName!.trim().toLowerCase().startsWith('пользователь #')) {
      return rawDisplayName!.trim();
    }
    final full = [firstName, lastName]
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join(' ')
        .trim();
    if (full.isNotEmpty) return full;
    if (username != null && username!.trim().isNotEmpty) {
      return '@${username!.replaceFirst('@', '').trim()}';
    }
    if (rawDisplayName != null && rawDisplayName!.trim().isNotEmpty) {
      return rawDisplayName!.trim();
    }
    return id > 0 ? 'Пользователь #$id' : 'Пользователь';
  }

  /// Полный URL аватара пользователя
  String? get fullAvatarUrl {
    final raw = photoUrl;
    if (raw != null && raw.trim().isNotEmpty) {
      final s = raw.trim();
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
        if (s.startsWith('/')) {
          return 'https://aux.ganj4craft.ru$s';
        }
        return 'https://aux.ganj4craft.ru/$s';
      }
    }

    if (username != null && username!.trim().isNotEmpty) {
      final clean = username!.replaceFirst('@', '').trim();
      if (clean.isNotEmpty) {
        return 'https://unavatar.io/telegram/$clean';
      }
    }
    return null;
  }

  factory SocialUser.fromJson(Map<String, dynamic> rawJson) {
    final Map<String, dynamic> json = (rawJson['user'] is Map<String, dynamic>)
        ? rawJson['user'] as Map<String, dynamic>
        : (rawJson['uploader'] is Map<String, dynamic>)
            ? rawJson['uploader'] as Map<String, dynamic>
            : rawJson;

    final rawName = (json['display_name'] ??
            json['displayName'] ??
            json['name'] ??
            json['nickname'] ??
            json['uploader_name'] ??
            rawJson['display_name'] ??
            rawJson['displayName'] ??
            rawJson['name'] ??
            rawJson['nickname']) as String?;

    final uName = (json['username'] ?? rawJson['username']) as String?;
    final fName = (json['first_name'] ?? json['firstName'] ?? rawJson['first_name']) as String?;
    final lName = (json['last_name'] ?? json['lastName'] ?? rawJson['last_name']) as String?;
    final cNick = (json['custom_nickname'] ?? json['customNickname'] ?? rawJson['custom_nickname']) as String?;
    final pUrl = (json['custom_avatar_url'] ??
        json['customAvatarUrl'] ??
        json['photo_url'] ??
        json['photoUrl'] ??
        json['avatar_url'] ??
        json['avatarUrl'] ??
        json['avatar'] ??
        rawJson['photo_url'] ??
        rawJson['avatar_url'] ??
        rawJson['avatar']) as String?;

    return SocialUser(
      id: (json['id'] as num?)?.toInt() ??
          (json['user_id'] as num?)?.toInt() ??
          (rawJson['id'] as num?)?.toInt() ??
          (rawJson['user_id'] as num?)?.toInt() ??
          0,
      username: uName,
      firstName: fName,
      lastName: lName,
      customNickname: cNick,
      rawDisplayName: rawName,
      photoUrl: pUrl,
      bio: (json['bio'] ?? rawJson['bio']) as String?,
      followersCount: (json['followers_count'] as num?)?.toInt() ??
          (json['followersCount'] as num?)?.toInt() ??
          (rawJson['followers_count'] as num?)?.toInt() ??
          0,
      followingCount: (json['following_count'] as num?)?.toInt() ??
          (json['followingCount'] as num?)?.toInt() ??
          (rawJson['following_count'] as num?)?.toInt() ??
          0,
      trackCount: (json['track_count'] as num?)?.toInt() ??
          (json['trackCount'] as num?)?.toInt() ??
          (json['upload_count'] as num?)?.toInt() ??
          (rawJson['track_count'] as num?)?.toInt() ??
          (rawJson['upload_count'] as num?)?.toInt() ??
          0,
      playlistCount: (json['playlist_count'] as num?)?.toInt() ??
          (json['playlistCount'] as num?)?.toInt() ??
          (rawJson['playlist_count'] as num?)?.toInt() ??
          0,
      albumCount: (json['album_count'] as num?)?.toInt() ??
          (json['albumCount'] as num?)?.toInt() ??
          (rawJson['album_count'] as num?)?.toInt() ??
          0,
      isFollowing: json['is_following'] == true ||
          json['isFollowing'] == true ||
          rawJson['is_following'] == true,
      isMutual: json['is_mutual'] == true ||
          json['isMutual'] == true ||
          rawJson['is_mutual'] == true,
      channelTitle: (json['channel_title'] ??
          json['channelTitle'] ??
          rawJson['channel_title']) as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'first_name': firstName,
      'last_name': lastName,
      'custom_nickname': customNickname,
      'display_name': rawDisplayName,
      'photo_url': photoUrl,
      'bio': bio,
      'followers_count': followersCount,
      'following_count': followingCount,
      'track_count': trackCount,
      'playlist_count': playlistCount,
      'album_count': albumCount,
      'is_following': isFollowing,
      'is_mutual': isMutual,
      'channel_title': channelTitle,
    };
  }
}
