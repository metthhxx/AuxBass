import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  final String version;
  final String title;
  final String changelog;
  final String downloadUrl;
  final int size;

  UpdateInfo({
    required this.version,
    required this.title,
    required this.changelog,
    required this.downloadUrl,
    required this.size,
  });

  String get formattedSize {
    if (size <= 0) return '';
    final mb = size / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} МБ';
  }
}

class UpdateService {
  static const String currentVersion = '1.0.0';
  static String githubOwner = 'AuxBass';
  static String githubRepo = 'AuxBass';

  static void configureRepo(String owner, String repo) {
    githubOwner = owner;
    githubRepo = repo;
  }

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/vnd.github.v3+json',
      },
    ),
  );

  /// Проверить наличие свежего релиза на GitHub
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final res = await _dio.get(
        'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest',
      );
      if (res.statusCode != 200 || res.data == null) return null;

      final data = res.data as Map<String, dynamic>;
      final rawTag = (data['tag_name'] as String? ?? '').replaceFirst('v', '').trim();
      if (rawTag.isEmpty) return null;

      if (_isNewer(rawTag, currentVersion)) {
        final assets = data['assets'] as List<dynamic>? ?? [];
        String? apkUrl;
        int apkSize = 0;

        for (final a in assets) {
          if (a is Map) {
            final name = (a['name'] as String? ?? '').toLowerCase();
            if (name.endsWith('.apk')) {
              apkUrl = a['browser_download_url'] as String?;
              apkSize = (a['size'] as num?)?.toInt() ?? 0;
              break;
            }
          }
        }

        if (apkUrl != null) {
          return UpdateInfo(
            version: rawTag,
            title: data['name'] as String? ?? 'AuxBass v$rawTag',
            changelog: data['body'] as String? ?? 'Новое обновление доступно!',
            downloadUrl: apkUrl,
            size: apkSize,
          );
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Скачивание обновления и запуск системного установщика Android
  Future<void> downloadAndInstall(
    UpdateInfo update, {
    void Function(double progress)? onProgress,
  }) async {
    final cacheDir = await getTemporaryDirectory();
    final savePath = '${cacheDir.path}/AuxBass_update_${update.version}.apk';
    final file = File(savePath);
    if (await file.exists()) {
      await file.delete();
    }

    await _dio.download(
      update.downloadUrl,
      savePath,
      onReceiveProgress: (received, total) {
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      },
    );

    // Запуск системного установщика через MethodChannel
    const MethodChannel('ru.ganj4craft.aux/display').invokeMethod(
      'installApk',
      {'filePath': savePath},
    );
  }

  bool _isNewer(String latest, String current) {
    try {
      final lParts = latest.split('.').map(int.parse).toList();
      final cParts = current.split('.').map(int.parse).toList();
      for (int i = 0; i < 3; i++) {
        final l = i < lParts.length ? lParts[i] : 0;
        final c = i < cParts.length ? cParts[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }
      return false;
    } catch (_) {
      return latest != current;
    }
  }
}
