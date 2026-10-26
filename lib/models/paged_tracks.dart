import 'track.dart';

class PagedTracks {
  final int total;
  final int page;
  final int perPage;
  final List<Track> items;

  PagedTracks({
    required this.total,
    required this.page,
    required this.perPage,
    required this.items,
  });

  bool get hasMore => page * perPage < total;
}
