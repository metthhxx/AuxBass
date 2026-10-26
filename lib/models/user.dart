class User {
  final int id;
  final String? username;
  final String? firstName;
  final String? lastName;
  final String? photoUrl;
  final String? customAvatarUrl;
  final String? avatarUrl;

  User({
    required this.id,
    this.username,
    this.firstName,
    this.lastName,
    this.photoUrl,
    this.customAvatarUrl,
    this.avatarUrl,
  });

  String get displayName {
    if (firstName != null && firstName!.isNotEmpty) {
      if (lastName != null && lastName!.isNotEmpty) {
        return '$firstName $lastName';
      }
      return firstName!;
    }
    if (username != null && username!.isNotEmpty) {
      return '@$username';
    }
    return 'User #$id';
  }

  /// Полный URL аватара пользователя
  String? get fullAvatarUrl {
    final raw = customAvatarUrl ?? photoUrl ?? avatarUrl;
    if (raw != null && raw.trim().isNotEmpty) {
      final s = raw.trim();
      if (s.startsWith('http://') || s.startsWith('https://')) {
        return s;
      }
      if (s.startsWith('/')) {
        return 'https://aux.ganj4craft.ru$s';
      }
      return 'https://aux.ganj4craft.ru/$s';
    }

    // Если прямого URL аватара нет в профиле, берем Telegram юзерпик по username
    if (username != null && username!.isNotEmpty) {
      final clean = username!.replaceFirst('@', '').trim();
      if (clean.isNotEmpty) {
        return 'https://t.me/i/userpic/320/$clean.jpg';
      }
    }
    return null;
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      username: json['username'] as String?,
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      photoUrl: (json['photo_url'] ?? json['photoUrl']) as String?,
      customAvatarUrl: (json['custom_avatar_url'] ?? json['customAvatarUrl']) as String?,
      avatarUrl: (json['avatar_url'] ?? json['avatarUrl'] ?? json['avatar']) as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'first_name': firstName,
      'last_name': lastName,
      'photo_url': photoUrl,
      'custom_avatar_url': customAvatarUrl,
      'avatar_url': avatarUrl,
    };
  }
}
