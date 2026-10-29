import 'social_user.dart';
import 'track.dart';

class FeedDrop {
  final String id;
  final SocialUser? uploader;
  final String action;
  final String? createdAt;
  final List<Track> tracks;

  FeedDrop({
    required this.id,
    this.uploader,
    this.action = 'добавил новые треки',
    this.createdAt,
    required this.tracks,
  });

  factory FeedDrop.fromJson(Map<String, dynamic> json) {
    SocialUser? user;
    if (json['uploader'] is Map<String, dynamic>) {
      user = SocialUser.fromJson(json['uploader'] as Map<String, dynamic>);
    } else if (json['user'] is Map<String, dynamic>) {
      user = SocialUser.fromJson(json['user'] as Map<String, dynamic>);
    } else if (json['user_id'] != null || json['uploader_id'] != null || json['username'] != null || json['display_name'] != null) {
      user = SocialUser.fromJson(json);
    }

    final rawTracks = json['tracks'];
    final tracksList = <Track>[];
    if (rawTracks is List) {
      for (final item in rawTracks) {
        if (item is Map<String, dynamic>) {
          tracksList.add(Track.fromJson(item));
        }
      }
    } else if (json['track'] is Map<String, dynamic>) {
      tracksList.add(Track.fromJson(json['track'] as Map<String, dynamic>));
    } else if (json['file_name'] != null || json['title'] != null) {
      tracksList.add(Track.fromJson(json));
    }

    return FeedDrop(
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      uploader: user,
      action: json['action'] as String? ?? 'добавил треки',
      createdAt: json['created_at'] as String?,
      tracks: tracksList,
    );
  }
}
