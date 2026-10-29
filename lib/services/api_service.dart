import 'package:dio/dio.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../models/feed_drop.dart';
import '../models/global_user.dart';
import '../models/music_tag.dart';
import '../models/paged_tracks.dart';
import '../models/playlist.dart';
import '../models/social_user.dart';
import '../models/track.dart';
import 'auth_service.dart';

class ApiService {
  static const String baseUrl = 'https://aux.ganj4craft.ru/api';
  final AuthService _authService = AuthService();
  late final Dio _dio;

  ApiService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );

    // Интерцептор для автоматической подстановки токена авторизации
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _authService.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
      ),
    );
  }

  /// Получение одной страницы библиотеки (макс 100 треков)
  Future<PagedTracks> getLibraryTracksPage({int page = 1, int perPage = 100}) async {
    try {
      final response = await _dio.get(
        '/tracks',
        queryParameters: {'page': page, 'per_page': perPage},
      );
      final items = _parseTracks(response.data);
      final total = (response.data is Map && response.data['total'] != null)
          ? (response.data['total'] as num).toInt()
          : items.length;
      return PagedTracks(
        total: total,
        page: page,
        perPage: perPage,
        items: items,
      );
    } catch (e) {
      throw Exception('Не удалось загрузить библиотеку: $e');
    }
  }

  /// Получение всех треков библиотеки пользователя (все страницы до total)
  Future<List<Track>> getAllLibraryTracks({
    void Function(List<Track> currentLoaded, int total)? onProgress,
  }) async {
    final firstPage = await getLibraryTracksPage(page: 1, perPage: 100);
    final allTracks = List<Track>.from(firstPage.items);
    final total = firstPage.total;

    onProgress?.call(List.unmodifiable(allTracks), total);

    final totalPages = (total / 100).ceil();
    if (totalPages > 1) {
      // Загружаем оставшиеся страницы пачками по 3 параллельно
      for (int p = 2; p <= totalPages; p += 3) {
        final chunk = <Future<PagedTracks>>[];
        for (int i = p; i < p + 3 && i <= totalPages; i++) {
          chunk.add(getLibraryTracksPage(page: i, perPage: 100));
        }
        final results = await Future.wait(chunk);
        for (final r in results) {
          allTracks.addAll(r.items);
        }
        onProgress?.call(List.unmodifiable(allTracks), total);
      }
    }
    return allTracks;
  }

  /// Получение всех любимых (лайкнутых) треков (все страницы)
  Future<List<Track>> getAllLikedTracks({
    void Function(List<Track> currentLoaded, int total)? onProgress,
  }) async {
    try {
      final firstRes = await _dio.get(
        '/tracks/liked',
        queryParameters: {'page': 1, 'per_page': 100},
      );
      final firstItems = _parseTracks(firstRes.data);
      for (final t in firstItems) {
        t.isLiked = true;
      }
      final all = List<Track>.from(firstItems);
      final total = (firstRes.data is Map && firstRes.data['total'] != null)
          ? (firstRes.data['total'] as num).toInt()
          : all.length;

      onProgress?.call(List.unmodifiable(all), total);

      final totalPages = (total / 100).ceil();
      if (totalPages > 1) {
        for (int p = 2; p <= totalPages; p += 3) {
          final chunk = <Future<Response>>[];
          for (int i = p; i < p + 3 && i <= totalPages; i++) {
            chunk.add(_dio.get('/tracks/liked', queryParameters: {'page': i, 'per_page': 100}));
          }
          final responses = await Future.wait(chunk);
          for (final res in responses) {
            final items = _parseTracks(res.data);
            for (final t in items) {
              t.isLiked = true;
            }
            all.addAll(items);
          }
          onProgress?.call(List.unmodifiable(all), total);
        }
      }
      return all;
    } catch (e) {
      throw Exception('Не удалось загрузить любимые треки: $e');
    }
  }

  /// Получение истории прослушиваний (до 100 треков)
  Future<List<Track>> getHistoryTracks({int limit = 100}) async {
    try {
      final response = await _dio.get(
        '/tracks/history',
        queryParameters: {'limit': limit},
      );
      return _parseTracks(response.data);
    } catch (e) {
      throw Exception('Не удалось загрузить историю: $e');
    }
  }

  /// Получение страницы глобального каталога треков (с метаданными total, page, perPage)
  Future<PagedTracks> getGlobalTracksPage({int page = 1, int perPage = 100}) async {
    try {
      final response = await _dio.get(
        '/tracks/global',
        queryParameters: {'page': page, 'per_page': perPage},
      );
      final items = _parseTracks(response.data);
      final total = (response.data is Map && response.data['total'] != null)
          ? (response.data['total'] as num).toInt()
          : items.length;
      return PagedTracks(
        total: total,
        page: page,
        perPage: perPage,
        items: items,
      );
    } catch (e) {
      throw Exception('Не удалось загрузить глобальные треки: $e');
    }
  }

  /// Получение глобального чарта / популярных треков AuxBass
  Future<List<Track>> getGlobalTracks({int page = 1, int perPage = 100}) async {
    final paged = await getGlobalTracksPage(page: page, perPage: perPage);
    return paged.items;
  }

  /// Полнотекстовый поиск по всей базе треков на сервере (все 4800+ треков)
  Future<PagedTracks> searchGlobalTracks(String query, {int page = 1, int perPage = 100}) async {
    try {
      final response = await _dio.get(
        '/tracks/global',
        queryParameters: {'search': query.trim(), 'page': page, 'per_page': perPage},
      );
      final items = _parseTracks(response.data);
      final total = (response.data is Map && response.data['total'] != null)
          ? (response.data['total'] as num).toInt()
          : items.length;
      return PagedTracks(
        total: total,
        page: page,
        perPage: perPage,
        items: items,
      );
    } catch (e) {
      throw Exception('Ошибка поиска по сайту: $e');
    }
  }

  /// Шафл по всем трекам на сайте (случайная выборка из всей базы 4800+ треков сервера)
  Future<List<Track>> getRandomGlobalShuffle({int count = 100}) async {
    try {
      // 1. Узнаем точное общее количество треков
      final firstRes = await _dio.get('/tracks/global', queryParameters: {'page': 1, 'per_page': 100});
      final total = (firstRes.data is Map && firstRes.data['total'] != null)
          ? (firstRes.data['total'] as num).toInt()
          : 4800;
      final maxPage = (total / 100).ceil();

      // 2. Выбираем 3 случайные страницы из всей базы
      final now = DateTime.now().millisecondsSinceEpoch;
      final pages = <int>{};
      for (int i = 0; pages.length < 3 && i < 10; i++) {
        final p = 1 + ((now ~/ (i + 1) + i * 37) % maxPage);
        pages.add(p);
      }

      final futures = pages.map((p) => getGlobalTracks(page: p, perPage: 100));
      final results = await Future.wait(futures);

      final combined = <Track>[];
      for (final r in results) {
        combined.addAll(r);
      }
      combined.shuffle();
      return combined.take(count).toList();
    } catch (_) {
      final fallback = await getGlobalTracks(page: 1, perPage: 100);
      fallback.shuffle();
      return fallback;
    }
  }

  /// Получение списка плейлистов пользователя
  Future<List<Playlist>> getPlaylists() async {
    try {
      final response = await _dio.get('/playlists');
      if (response.data is List) {
        return (response.data as List)
            .map((p) => Playlist.fromJson(p as Map<String, dynamic>))
            .toList();
      }
      if (response.data is Map && response.data['items'] is List) {
        return (response.data['items'] as List)
            .map((p) => Playlist.fromJson(p as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Получение треков конкретного плейлиста
  Future<List<Track>> getPlaylistTracks(int playlistId) async {
    try {
      final response = await _dio.get('/playlists/$playlistId');
      return _parseTracks(response.data);
    } catch (e) {
      throw Exception('Не удалось загрузить треки плейлиста: $e');
    }
  }

  /// Создание нового плейлиста
  Future<Playlist> createPlaylist(String name) async {
    try {
      final response = await _dio.post('/playlists', data: {'name': name});
      return Playlist.fromJson(response.data);
    } catch (e) {
      throw Exception('Не удалось создать плейлист: $e');
    }
  }

  /// Переименование плейлиста
  Future<Playlist> updatePlaylist(int playlistId, String name) async {
    try {
      final response = await _dio.put('/playlists/$playlistId', data: {'name': name});
      return Playlist.fromJson(response.data);
    } catch (e) {
      throw Exception('Не удалось обновить плейлист: $e');
    }
  }

  /// Удаление плейлиста
  Future<bool> deletePlaylist(int playlistId) async {
    try {
      await _dio.delete('/playlists/$playlistId');
      return true;
    } catch (e) {
      throw Exception('Не удалось удалить плейлист: $e');
    }
  }

  /// Добавление трека в плейлист
  Future<bool> addTrackToPlaylist(int playlistId, int trackId) async {
    try {
      await _dio.post('/playlists/$playlistId/tracks', data: {'track_id': trackId});
      return true;
    } catch (e) {
      throw Exception('Не удалось добавить трек в плейлист: $e');
    }
  }

  /// Удаление трека из плейлиста
  Future<bool> removeTrackFromPlaylist(int playlistId, int trackId) async {
    try {
      await _dio.delete('/playlists/$playlistId/tracks/$trackId');
      return true;
    } catch (e) {
      throw Exception('Не удалось убрать трек из плейлиста: $e');
    }
  }

  /// Сохранение нового порядка треков в плейлисте
  Future<bool> reorderPlaylistTracks(int playlistId, List<int> trackIds) async {
    try {
      await _dio.put('/playlists/$playlistId/reorder', data: {'track_ids': trackIds});
      return true;
    } catch (e) {
      throw Exception('Не удалось изменить порядок треков: $e');
    }
  }

  /// Получение списка пользователей / авторов с сайта
  Future<List<GlobalUser>> getGlobalUsers({int limit = 50}) async {
    try {
      final response = await _dio.get('/tracks/global/users', queryParameters: {'limit': limit});
      if (response.data is List) {
        return (response.data as List)
            .map((u) => GlobalUser.fromJson(u as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      throw Exception('Не удалось загрузить пользователей: $e');
    }
  }

  /// Получение треков, загруженных конкретным пользователем
  Future<List<Track>> getUserTracks(int userId, {int limit = 100}) async {
    try {
      final response = await _dio.get(
        '/tracks/global/users/$userId/tracks',
        queryParameters: {'limit': limit},
      );
      return _parseTracks(response.data);
    } catch (e) {
      throw Exception('Не удалось загрузить треки пользователя: $e');
    }
  }

  /// Статус подключения SoundCloud
  Future<Map<String, dynamic>?> getSoundCloudAccount() async {
    try {
      final response = await _dio.get('/ingestion/account/soundcloud');
      return response.data as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// Подключение / синхронизация профиля SoundCloud
  Future<void> connectSoundCloud(String profileUrlOrUsername) async {
    try {
      await _dio.post(
        '/ingestion/account/soundcloud/connect',
        data: {'url': profileUrlOrUsername.trim()},
      );
    } catch (e) {
      // Пробуем альтернативное поле username
      try {
        await _dio.post(
          '/ingestion/account/soundcloud/connect',
          data: {'username': profileUrlOrUsername.trim()},
        );
      } on DioException catch (de) {
        if (de.response?.data is Map && de.response?.data['detail'] != null) {
          throw Exception(de.response?.data['detail'].toString());
        }
        throw Exception('Не удалось подключить SoundCloud: ${de.message}');
      }
    }
  }

  /// Получение ссылки на аудиопоток трека
  Future<String> getStreamUrl(int trackId) async {
    try {
      final response = await _dio.get('/player/stream/$trackId');
      final relativeUrl = response.data['url'] as String;
      if (relativeUrl.startsWith('http')) {
        return relativeUrl;
      }
      return 'https://aux.ganj4craft.ru$relativeUrl';
    } catch (e) {
      throw Exception('Не удалось получить поток аудио: $e');
    }
  }

  /// Фиксация прослушивания (скробблинг)
  Future<void> recordPlay(int trackId) async {
    try {
      await _dio.post('/player/play/$trackId');
    } catch (_) {}
  }

  /// Поставить или убрать лайк с трека
  Future<bool> toggleLike(int trackId, bool currentlyLiked) async {
    try {
      if (currentlyLiked) {
        await _dio.delete('/tracks/$trackId/like');
        return false;
      } else {
        await _dio.post('/tracks/$trackId/like');
        return true;
      }
    } catch (e) {
      throw Exception('Не удалось обновить статус лайка: $e');
    }
  }

  List<Track> _parseTracks(dynamic data) {
    if (data is Map && data.containsKey('items') && data['items'] is List) {
      return (data['items'] as List)
          .map((item) => Track.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    if (data is Map && data.containsKey('tracks') && data['tracks'] is List) {
      return (data['tracks'] as List)
          .map((item) => Track.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    if (data is List) {
      return data
          .map((item) => Track.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  // ==========================================
  // 1. СОЦИАЛЬНЫЙ ФУНКЦИОНАЛ («КЕНТЫ»)
  // ==========================================

  /// Получение ленты активности (updates от кентов)
  Future<List<FeedDrop>> getSocialFeed({String scope = 'following', int page = 1, int perPage = 30}) async {
    try {
      final response = await _dio.get(
        '/social/feed',
        queryParameters: {'scope': scope, 'page': page, 'per_page': perPage},
      );
      final data = response.data;
      final items = (data is Map && data['items'] is List)
          ? data['items'] as List
          : (data is List ? data : []);
      return items.map((i) => FeedDrop.fromJson(i as Map<String, dynamic>)).toList();
    } catch (e) {
      // Если подписок еще нет и following пуст, пробуем загрузить глобальную ленту
      if (scope == 'following') {
        try {
          return await getSocialFeed(scope: 'global', page: page, perPage: perPage);
        } catch (_) {}
      }
      return [];
    }
  }

  /// Список пользователей, на которых подписан текущий аккаунт
  Future<List<SocialUser>> getFollowing() async {
    try {
      final response = await _dio.get('/social/following');
      final data = response.data;
      final list = (data is Map && data['items'] is List)
          ? data['items'] as List
          : (data is List ? data : []);
      return list.map((u) => SocialUser.fromJson(u as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Список подписчиков текущего аккаунта
  Future<List<SocialUser>> getFollowers() async {
    try {
      final response = await _dio.get('/social/followers');
      final data = response.data;
      final list = (data is Map && data['items'] is List)
          ? data['items'] as List
          : (data is List ? data : []);
      return list.map((u) => SocialUser.fromJson(u as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Поиск кентов/пользователей по нику или имени
  Future<List<SocialUser>> searchSocialUsers(String query, {int page = 1, int perPage = 30}) async {
    try {
      final response = await _dio.get(
        '/social/search',
        queryParameters: {'q': query.trim(), 'page': page, 'per_page': perPage},
      );
      final data = response.data;
      final list = (data is Map && data['items'] is List)
          ? data['items'] as List
          : (data is List ? data : []);
      return list.map((u) => SocialUser.fromJson(u as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Подписаться на пользователя
  Future<bool> followUser(int userId) async {
    try {
      await _dio.post('/social/follow', data: {'user_id': userId});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Отписаться от пользователя
  Future<bool> unfollowUser(int userId) async {
    try {
      await _dio.post('/social/unfollow', data: {'user_id': userId});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Получить подробный профиль пользователя
  Future<SocialUser> getUserProfile(int userId) async {
    try {
      final response = await _dio.get('/social/user/$userId');
      final data = response.data is Map ? response.data as Map<String, dynamic> : <String, dynamic>{};
      return SocialUser.fromJson(data);
    } catch (e) {
      throw Exception('Не удалось загрузить профиль пользователя: $e');
    }
  }

  /// Медиатека треков конкретного пользователя
  Future<List<Track>> getUserLibrary(int userId, {int page = 1, int perPage = 100}) async {
    try {
      final response = await _dio.get(
        '/social/user/$userId/library',
        queryParameters: {'page': page, 'per_page': perPage},
      );
      return _parseTracks(response.data);
    } catch (_) {
      return getUserTracks(userId, limit: perPage);
    }
  }

  /// Альбомы конкретного пользователя
  Future<List<Album>> getUserAlbums(int userId) async {
    try {
      final response = await _dio.get('/social/user/$userId/albums');
      final data = response.data;
      final list = (data is Map && data['items'] is List)
          ? data['items'] as List
          : (data is List ? data : []);
      return list.map((a) => Album.fromJson(a as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Плейлисты конкретного пользователя
  Future<List<Playlist>> getUserPlaylists(int userId) async {
    try {
      final response = await _dio.get('/playlists/user/$userId');
      final data = response.data;
      final list = (data is Map && data['items'] is List)
          ? data['items'] as List
          : (data is List ? data : []);
      return list.map((p) => Playlist.fromJson(p as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  // ==========================================
  // 2. АЛЬБОМЫ И АРТИСТЫ (КАТАЛОГ)
  // ==========================================

  /// Список альбомов (scope: 'library' или 'global')
  Future<List<Album>> getAlbums({String scope = 'library'}) async {
    try {
      final response = await _dio.get('/albums', queryParameters: {'scope': scope});
      final data = response.data;
      final list = (data is Map && data['items'] is List)
          ? data['items'] as List
          : (data is List ? data : []);
      if (list.isEmpty && scope == 'library') {
        // Fallback к глобальным альбомам
        return await getAlbums(scope: 'global');
      }
      return list.map((a) => Album.fromJson(a as Map<String, dynamic>)).toList();
    } catch (e) {
      if (scope == 'library') {
        try {
          return await getAlbums(scope: 'global');
        } catch (_) {}
      }
      return [];
    }
  }

  /// Детали альбома со списком всех треков
  Future<Album> getAlbumDetails(dynamic albumId, {String scope = 'library'}) async {
    try {
      Response response;
      try {
        response = await _dio.get('/albums/$albumId', queryParameters: {'scope': scope});
      } on DioException catch (de) {
        if (de.response?.statusCode == 404 && scope == 'library') {
          response = await _dio.get('/albums/$albumId', queryParameters: {'scope': 'global'});
        } else {
          rethrow;
        }
      }
      final data = response.data is Map ? response.data as Map<String, dynamic> : <String, dynamic>{};
      return Album.fromJson(data);
    } catch (e) {
      throw Exception('Не удалось загрузить альбом: $e');
    }
  }

  /// Список артистов (scope: 'library' или 'global')
  Future<List<Artist>> getArtists({String scope = 'library'}) async {
    try {
      final response = await _dio.get('/artists', queryParameters: {'scope': scope, 'limit': 150});
      final data = response.data;
      final list = (data is Map && data['items'] is List)
          ? data['items'] as List
          : (data is List ? data : []);
      if (list.isEmpty && scope == 'library') {
        return await getArtists(scope: 'global');
      }
      return list.map((a) => Artist.fromJson(a as Map<String, dynamic>)).toList();
    } catch (_) {
      if (scope == 'library') {
        try {
          return await getArtists(scope: 'global');
        } catch (_) {}
      }
      return [];
    }
  }

  /// Информация об исполнителе (инфо, дискография/альбомы)
  Future<Artist> getArtistInfo(String artistName, {String scope = 'library'}) async {
    try {
      Response response;
      final encoded = Uri.encodeComponent(artistName);
      try {
        response = await _dio.get('/artists/$encoded/info', queryParameters: {'scope': scope});
      } on DioException catch (de) {
        if (de.response?.statusCode == 404 && scope == 'library') {
          response = await _dio.get('/artists/$encoded/info', queryParameters: {'scope': 'global'});
        } else {
          rethrow;
        }
      }
      final data = response.data is Map ? response.data as Map<String, dynamic> : <String, dynamic>{};
      return Artist.fromJson(data);
    } catch (_) {
      return Artist(name: artistName);
    }
  }

  /// Треки конкретного артиста
  Future<List<Track>> getArtistTracks(String artistName, {String scope = 'library', int limit = 100}) async {
    try {
      final encoded = Uri.encodeComponent(artistName);
      final response = await _dio.get(
        '/artists/$encoded/tracks',
        queryParameters: {'scope': scope, 'limit': limit},
      );
      return _parseTracks(response.data);
    } catch (_) {
      return [];
    }
  }

  /// Добавить трек в свою медиатеку
  Future<bool> addTrackToLibrary(int trackId) async {
    try {
      await _dio.post('/tracks/$trackId/add-to-library');
      return true;
    } catch (_) {
      return false;
    }
  }

  // ==========================================
  // 7. ЖАНРЫ, ТЕГИ И РЕКОМЕНДАЦИИ
  // ==========================================

  /// Получить популярные теги
  Future<List<MusicTag>> getTags({String scope = 'global', int limit = 40}) async {
    try {
      final response = await _dio.get('/tracks/tags', queryParameters: {'scope': scope, 'limit': limit});
      final data = response.data;
      final list = (data is Map && data['items'] is List)
          ? data['items'] as List
          : (data is List ? data : []);
      if (list.isEmpty && scope == 'library') {
        return await getTags(scope: 'global', limit: limit);
      }
      final tags = list.map((t) => MusicTag.fromJson(t)).toList();
      return tags.isNotEmpty ? tags : _defaultTags;
    } catch (_) {
      return _defaultTags;
    }
  }

  /// Получить список жанров
  Future<List<String>> getGenres({String scope = 'global'}) async {
    try {
      final response = await _dio.get('/tracks/genres', queryParameters: {'scope': scope});
      final data = response.data;
      final list = (data is Map && data['genres'] is List)
          ? data['genres'] as List
          : (data is List ? data : []);
      return list.map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  /// Популярные треки на AuxBass (топ)
  Future<List<Track>> getGlobalPopular({int limit = 20}) async {
    try {
      final response = await _dio.get('/tracks/global/popular', queryParameters: {'limit': limit});
      return _parseTracks(response.data);
    } catch (_) {
      return [];
    }
  }

  /// Новые поступления треков на AuxBass (свежие добавления)
  Future<List<Track>> getGlobalRecent({int limit = 20}) async {
    try {
      final response = await _dio.get('/tracks/global/recent', queryParameters: {'limit': limit});
      return _parseTracks(response.data);
    } catch (_) {
      return [];
    }
  }

  static final List<MusicTag> _defaultTags = [
    MusicTag(name: 'phonk'),
    MusicTag(name: 'lo-fi'),
    MusicTag(name: 'dnb'),
    MusicTag(name: 'rock'),
    MusicTag(name: 'hiphop'),
    MusicTag(name: 'ambient'),
    MusicTag(name: 'synthwave'),
    MusicTag(name: 'chill'),
    MusicTag(name: 'nightdrive'),
    MusicTag(name: 'electronic'),
    MusicTag(name: 'indie'),
    MusicTag(name: 'workout'),
  ];
}
