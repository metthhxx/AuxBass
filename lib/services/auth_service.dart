import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/auth_response.dart';
import '../models/user.dart';

class AuthService {
  static const String baseUrl = 'https://aux.ganj4craft.ru/api';
  static const String _tokenKey = 'tg_player_auth_token';
  static const String _userKey = 'tg_player_auth_user';

  final Dio _dio = Dio(
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

  /// Отправка кода из Telegram-бота (@auxbassbot) для авторизации
  Future<AuthResponse> verifyCode(String code) async {
    try {
      final response = await _dio.post(
        '/auth/verify-code',
        data: {'code': code.trim()},
      );

      final authResponse = AuthResponse.fromJson(response.data);

      // Сохраняем сессию
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, authResponse.token);
      if (authResponse.user != null) {
        await prefs.setString(_userKey, jsonEncode(authResponse.user!.toJson()));
      }

      return authResponse;
    } on DioException catch (e) {
      if (e.response != null && e.response?.data != null) {
        final data = e.response!.data;
        if (data is Map && data.containsKey('detail')) {
          throw Exception(data['detail'].toString());
        }
      }
      throw Exception('Ошибка подключения к серверу: ${e.message}');
    } catch (e) {
      throw Exception('Непредвиденная ошибка: $e');
    }
  }

  /// Получение сохраненного токена
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  /// Получение сохраненного пользователя
  Future<User?> getSavedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userStr = prefs.getString(_userKey);
    if (userStr == null) return null;
    try {
      return User.fromJson(jsonDecode(userStr));
    } catch (_) {
      return null;
    }
  }

  /// Проверка валидности сессии через /api/auth/me
  Future<User?> validateSession() async {
    final token = await getToken();
    if (token == null) return null;

    try {
      final response = await _dio.get(
        '/auth/me',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      final user = User.fromJson(response.data);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userKey, jsonEncode(user.toJson()));
      return user;
    } catch (_) {
      // Если токен протух
      await logout();
      return null;
    }
  }

  /// Выход из аккаунта
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }
}
