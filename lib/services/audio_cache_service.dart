import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Сервис локального кэширования аудиотреков на диск для мгновенного старта и оффлайн-воспроизведения
class AudioCacheService {
  static final AudioCacheService _instance = AudioCacheService._internal();
  factory AudioCacheService() => _instance;
  AudioCacheService._internal();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );

  Directory? _cacheDir;
  final Map<int, Future<File?>> _activeDownloads = {};
  static const int maxCacheBytes = 1500 * 1024 * 1024; // 1.5 ГБ лимит кэша

  Future<void> init() async {
    if (_cacheDir != null) return;
    try {
      final baseDir = await getApplicationSupportDirectory();
      _cacheDir = Directory('${baseDir.path}/audio_cache');
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
    } catch (e) {
      debugPrint('[AudioCacheService] Ошибка инициализации папки кэша: $e');
    }
  }

  File _getTrackFile(int trackId) {
    return File('${_cacheDir!.path}/$trackId.mp3');
  }

  /// Проверить, скачан ли трек в кэш полностью
  bool isCached(int trackId) {
    if (_cacheDir == null) return false;
    final file = _getTrackFile(trackId);
    return file.existsSync() && file.lengthSync() > 1024; // валидный файл > 1KB
  }

  /// Получить локальный файл трека из кэша (если существует)
  File? getCachedFile(int trackId) {
    if (isCached(trackId)) {
      return _getTrackFile(trackId);
    }
    return null;
  }

  /// Фоновая загрузка трека в кэш
  Future<File?> cacheTrackInBackground(int trackId, String streamUrl) {
    if (isCached(trackId)) {
      return Future.value(_getTrackFile(trackId));
    }

    // Если этот трек уже прямо сейчас скачивается — возвращаем существующий Future
    if (_activeDownloads.containsKey(trackId)) {
      return _activeDownloads[trackId]!;
    }

    final completer = Completer<File?>();
    _activeDownloads[trackId] = completer.future;

    _doDownload(trackId, streamUrl).then((file) {
      completer.complete(file);
      _activeDownloads.remove(trackId);
      _enforceMaxCacheSize();
    }).catchError((e) {
      debugPrint('[AudioCacheService] Ошибка фоновой загрузки $trackId: $e');
      completer.complete(null);
      _activeDownloads.remove(trackId);
    });

    return completer.future;
  }

  Future<File?> _doDownload(int trackId, String streamUrl) async {
    await init();
    if (_cacheDir == null) return null;

    final targetFile = _getTrackFile(trackId);
    final tempFile = File('${_cacheDir!.path}/$trackId.tmp');

    try {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      await _dio.download(
        streamUrl,
        tempFile.path,
        deleteOnError: true,
      );

      if (await tempFile.exists() && await tempFile.length() > 1024) {
        await tempFile.rename(targetFile.path);
        debugPrint('[AudioCacheService] Трек $trackId успешно закэширован: ${targetFile.lengthSync()} байт');
        return targetFile;
      } else {
        if (await tempFile.exists()) await tempFile.delete();
        return null;
      }
    } catch (e) {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      return null;
    }
  }

  /// Предзагрузка трека (preload) для бесшовного перехода
  Future<void> preloadTrack(int trackId, Future<String> Function() getStreamUrl) async {
    if (isCached(trackId) || _activeDownloads.containsKey(trackId)) {
      return;
    }

    try {
      debugPrint('[AudioCacheService] Предзагрузка следующего трека $trackId для бесшовного перехода...');
      final streamUrl = await getStreamUrl();
      await cacheTrackInBackground(trackId, streamUrl);
    } catch (e) {
      debugPrint('[AudioCacheService] Ошибка предзагрузки трека $trackId: $e');
    }
  }

  /// Получить общий размер кэша в байтах
  Future<int> getCacheSizeBytes() async {
    await init();
    if (_cacheDir == null || !await _cacheDir!.exists()) return 0;

    int totalSize = 0;
    try {
      final list = _cacheDir!.listSync();
      for (final entity in list) {
        if (entity is File) {
          totalSize += entity.lengthSync();
        }
      }
    } catch (e) {
      debugPrint('[AudioCacheService] Ошибка подсчета размера кэша: $e');
    }
    return totalSize;
  }

  /// Отформатированный размер кэша (например "145.2 МБ")
  Future<String> getFormattedCacheSize() async {
    final bytes = await getCacheSizeBytes();
    if (bytes <= 0) return '0 МБ';
    final mb = bytes / (1024 * 1024);
    if (mb < 1024) {
      return '${mb.toStringAsFixed(1)} МБ';
    }
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} ГБ';
  }

  /// Полная очистка кэша аудио
  Future<void> clearCache() async {
    await init();
    if (_cacheDir == null || !await _cacheDir!.exists()) return;

    try {
      final list = _cacheDir!.listSync();
      for (final entity in list) {
        if (entity is File) {
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
      debugPrint('[AudioCacheService] Кэш аудио успешно очищен');
    } catch (e) {
      debugPrint('[AudioCacheService] Ошибка очистки кэша: $e');
    }
  }

  /// Автоматическое удаление старых файлов (LRU), если кэш превысил лимит
  Future<void> _enforceMaxCacheSize() async {
    try {
      if (_cacheDir == null) return;
      final files = _cacheDir!
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.mp3'))
          .toList();

      int totalSize = files.fold(0, (acc, f) => acc + f.lengthSync());
      if (totalSize <= maxCacheBytes) return;

      // Сортируем по времени последней модификации / доступа (старые первыми)
      files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));

      for (final file in files) {
        if (totalSize <= (maxCacheBytes * 0.7)) break; // чистим до 70% от лимита
        final len = file.lengthSync();
        try {
          file.deleteSync();
          totalSize -= len;
          debugPrint('[AudioCacheService] LRU удалил старый файл кэша: ${file.path}');
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[AudioCacheService] Ошибка очистки LRU кэша: $e');
    }
  }
}
