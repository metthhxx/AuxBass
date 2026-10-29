import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/user.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/audio_player_handler.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';

late final AudioPlayerHandler audioHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Принудительная блокировка портретной ориентации (без автоповорота)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Принудительное включение максимальной герцовки дисплея (144Hz / 120Hz)
  try {
    const MethodChannel('ru.ganj4craft.aux/display').invokeMethod('setHighRefreshRate');
  } catch (_) {}

  // Инициализация фоновой службы воспроизведения музыки Android
  audioHandler = await AudioService.init(
    builder: () => AudioPlayerHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'ru.ganj4craft.aux.channel.audio',
      androidNotificationChannelName: 'AuxBass Music',
      androidNotificationChannelDescription: 'Воспроизведение музыки AuxBass',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
      androidNotificationIcon: 'drawable/ic_notification',
      artDownscaleWidth: 512,
      artDownscaleHeight: 512,
    ),
  );

  runApp(const AuxApp());
}

class AuxApp extends StatelessWidget {
  const AuxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AuxBass',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: AppTheme.darkTheme,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AuthService _authService = AuthService();
  bool _isChecking = true;
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _checkInitialAuth();
  }

  Future<void> _checkInitialAuth() async {
    final cachedUser = await _authService.getSavedUser();
    if (cachedUser != null) {
      if (mounted) {
        setState(() {
          _currentUser = cachedUser;
          _isChecking = false;
        });
      }
      _authService.validateSession();
      return;
    }

    final user = await _authService.validateSession();
    if (mounted) {
      setState(() {
        _currentUser = user;
        _isChecking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        backgroundColor: AppTheme.bg0,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accent),
          ),
        ),
      );
    }

    if (_currentUser != null) {
      return HomeScreen(user: _currentUser!, audioHandler: audioHandler);
    }

    return LoginScreen(audioHandler: audioHandler);
  }
}
