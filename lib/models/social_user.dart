class SocialUser {
  final int id;
  final String? username;
  final String? firstName;
  final String? lastName;
  final String? customNickname;
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
    final full = [firstName, lastName].whereType<String>().where((s) => s.isNotEmpty).join(' ').trim();
    if (full.isNotEmpty) return full;
    if (username != null && username!.trim().isNotEmpty) return '@$username';
    return 'Пользователь #$id';
  }

  factory SocialUser.fromJson(Map<String, dynamic> json) {
    return SocialUser(
      id: (json['id'] as num?)?.toInt() ?? 0,
      username: json['username'] as String?,
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      customNickname: json['custom_nickname'] as String?,
      photoUrl: json['custom_avatar_url'] as String? ?? json['photo_url'] as String? ?? json['avatar_url'] as String?,
      bio: json['bio'] as String?,
      followersCount: (json['followers_count'] as num?)?.toInt() ?? 0,
      followingCount: (json['following_count'] as num?)?.toInt() ?? 0,
      trackCount: (json['track_count'] as num?)?.toInt() ?? 0,
      playlistCount: (json['playlist_count'] as num?)?.toInt() ?? 0,
      albumCount: (json['album_count'] as num?)?.toInt() ?? 0,
      isFollowing: json['is_following'] == true,
      isMutual: json['is_mutual'] == true,
      channelTitle: json['channel_title'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'first_name': firstName,
      'last_name': lastName,
      'custom_nickname': customNickname,
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
