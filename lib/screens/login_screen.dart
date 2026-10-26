import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/audio_player_handler.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  final AudioPlayerHandler audioHandler;

  const LoginScreen({super.key, required this.audioHandler});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _codeController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _openTelegramBot() async {
    // 1. Пробуем прямой протокол Telegram-приложения
    final tgUri = Uri.parse('tg://resolve?domain=auxbassbot');
    try {
      final launched = await launchUrl(tgUri, mode: LaunchMode.externalNonBrowserApplication);
      if (launched) return;
    } catch (_) {}

    // 2. Если не открылось, пробуем обычный URL без браузера
    final tmeUri = Uri.parse('https://t.me/auxbassbot');
    if (!await launchUrl(tmeUri, mode: LaunchMode.externalNonBrowserApplication)) {
      // 3. Fallback в браузер только при отсутствии клиента
      if (!await launchUrl(tmeUri, mode: LaunchMode.externalApplication)) {
        setState(() {
          _errorMessage = 'Не удалось открыть Telegram. Найдите @auxbassbot вручную.';
        });
      }
    }
  }

  Future<void> _submitCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _errorMessage = 'Введите код авторизации';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _authService.verifyCode(code);
      if (!mounted) return;

      final user = response.user;
      if (user != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => HomeScreen(user: user, audioHandler: widget.audioHandler)),
        );
      } else {
        final validatedUser = await _authService.validateSession();
        if (!mounted) return;
        if (validatedUser != null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => HomeScreen(user: validatedUser, audioHandler: widget.audioHandler)),
          );
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg0,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Логотип AuxBass с фирменным зеленым свечением
                Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.accent, AppTheme.accentLight],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: const [
                        BoxShadow(
                          color: AppTheme.accentGlow,
                          blurRadius: 28,
                          spreadRadius: 2,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.graphic_eq_rounded,
                      size: 48,
                      color: AppTheme.accentText,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                const Text(
                  'AuxBass',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                const _MinecraftSplashText(
                  text: 'Вайбкод на вайбкоде, вайбкодингом погоняют',
                ),
                const SizedBox(height: 36),

                // Карточка с инструкцией (стиль Spotify / AuxBass)
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppTheme.bg2,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppTheme.bg4),
                  ),
                  child: Column(
                    children: [
                      const _StepRow(
                        step: '1',
                        text: 'Перейдите в Telegram-бота @auxbassbot',
                      ),
                      const SizedBox(height: 14),
                      const _StepRow(
                        step: '2',
                        text: 'Нажмите «Получить код для входа» (или команду /code)',
                      ),
                      const SizedBox(height: 14),
                      const _StepRow(
                        step: '3',
                        text: 'Введите полученный код в поле ниже',
                      ),
                      const SizedBox(height: 18),

                      // Кнопка перехода в бота
                      OutlinedButton.icon(
                        onPressed: _openTelegramBot,
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: const Text('Открыть @auxbassbot'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.accentLight,
                          side: const BorderSide(color: AppTheme.accent, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Ошибка при авторизации
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0x26E53935),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0x66E53935)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Color(0xFFFF5252), size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 13, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Поле ввода кода
                TextField(
                  controller: _codeController,
                  autocorrect: false,
                  enableSuggestions: false,
                  cursorColor: AppTheme.accent,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'КОД ВХОДА',
                    hintStyle: const TextStyle(
                      fontSize: 16,
                      letterSpacing: 2,
                      color: AppTheme.textMuted,
                    ),
                    filled: true,
                    fillColor: AppTheme.bg3,
                    contentPadding: const EdgeInsets.symmetric(vertical: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: AppTheme.bg4),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: AppTheme.accent, width: 2),
                    ),
                  ),
                  onSubmitted: (_) => _submitCode(),
                ),
                const SizedBox(height: 16),

                // Фирменная зелёная кнопка "Войти" с темным жирным текстом (как на сайте)
                ElevatedButton(
                  onPressed: _isLoading ? null : _submitCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: AppTheme.accentText,
                    disabledBackgroundColor: AppTheme.accentDark.withAlpha(128),
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentText),
                          ),
                        )
                      : const Text(
                          'Войти в аккаунт',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String step;
  final String text;

  const _StepRow({required this.step, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.accent.withAlpha(35),
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.accent.withAlpha(80)),
          ),
          child: Text(
            step,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppTheme.accentLight,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13.5,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _MinecraftSplashText extends StatefulWidget {
  final String text;
  const _MinecraftSplashText({required this.text});

  @override
  State<_MinecraftSplashText> createState() => _MinecraftSplashTextState();
}

class _MinecraftSplashTextState extends State<_MinecraftSplashText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    // Плавная пульсация масштаба как в главном меню Minecraft
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.94, end: 1.08).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.rotate(
            angle: -0.22, // Наклон примерно -12.5° как в Minecraft
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: child,
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(
            widget.text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Minecraft',
              color: Color(0xFFFFFF55), // Каноничный желтый цвет Minecraft Splash Text
              fontSize: 15.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              shadows: [
                Shadow(
                  color: Color(0xFF3F3F15), // Тень Minecraft
                  offset: Offset(2, 2),
                  blurRadius: 0,
                ),
                Shadow(
                  color: Colors.black87,
                  offset: Offset(3, 3),
                  blurRadius: 1,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
