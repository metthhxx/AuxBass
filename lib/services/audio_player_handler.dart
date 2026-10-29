import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import 'api_service.dart';

/// Глобальный обработчик воспроизведения аудио с поддержкой системных уведомлений
class AudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer(
    audioLoadConfiguration: const AudioLoadConfiguration(
      androidLoadControl: AndroidLoadControl(
        minBufferDuration: Duration(seconds: 30),
        maxBufferDuration: Duration(seconds: 120),
        bufferForPlaybackDuration: Duration(milliseconds: 1500),
        bufferForPlaybackAfterRebufferDuration: Duration(seconds: 3),
        prioritizeTimeOverSizeThresholds: true,
      ),
    ),
  );
  final ApiService _apiService = ApiService();

  List<Track> _queue = [];
  int _currentIndex = -1;
  bool _isShuffle = false;
  LoopMode _loopMode = LoopMode.off;
  int _sessionCounter = 0;

  final ValueNotifier<Track?> currentTrackNotifier = ValueNotifier<Track?>(null);
  final ValueNotifier<List<Track>> queueNotifier = ValueNotifier<List<Track>>([]);

  AudioPlayer get player => _player;
  Track? get currentTrack => _currentIndex >= 0 && _currentIndex < _queue.length ? _queue[_currentIndex] : null;
  List<Track> get queueList => _queue;
  int get currentIndex => _currentIndex;
  bool get isShuffle => _isShuffle;
  LoopMode get loopMode => _loopMode;

  AudioPlayerHandler() {
    _initAudioSession();
    _listenToPlayerEvents();
  }

  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // Обработка прерываний (звонки, другие приложения)
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            _player.setVolume(0.5);
            break;
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            pause();
            break;
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            _player.setVolume(1.0);
            break;
          case AudioInterruptionType.pause:
            play();
            break;
          case AudioInterruptionType.unknown:
            break;
        }
      }
    });
  }

  void _listenToPlayerEvents() {
    // Синхронизация состояния плеера с системным AudioService (шторка уведомлений Android)
    _player.playbackEventStream.listen((_) => _broadcastState());

    // Отслеживание изменений состояния и автоматический переход к следующему треку
    _player.playerStateStream.listen((state) {
      _broadcastState();
      if (state.processingState == ProcessingState.completed) {
        if (_loopMode == LoopMode.one) {
          seek(Duration.zero);
          play();
        } else {
          skipToNext();
        }
      }
    });
  }

  void _broadcastState() {
    final playing = _player.playing;
    final track = currentTrack;

    AudioProcessingState processingState;
    switch (_player.processingState) {
      case ProcessingState.idle:
        // Если трек выбран или загружается — не шлем idle, чтобы Android не убивал службу и шторку
        processingState = track != null
            ? AudioProcessingState.loading
            : AudioProcessingState.idle;
        break;
      case ProcessingState.loading:
        processingState = AudioProcessingState.loading;
        break;
      case ProcessingState.buffering:
        processingState = AudioProcessingState.buffering;
        break;
      case ProcessingState.ready:
        processingState = AudioProcessingState.ready;
        break;
      case ProcessingState.completed:
        processingState = AudioProcessingState.completed;
        break;
    }

    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processingState,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _currentIndex,
      ),
    );
  }

  /// Установить очередь воспроизведения и начать проигрывать с указанного индекса
  Future<void> playTrackList(List<Track> tracks, int startIndex) async {
    if (tracks.isEmpty || startIndex < 0 || startIndex >= tracks.length) return;

    _queue = List.from(tracks);
    _currentIndex = startIndex;
    queueNotifier.value = List.unmodifiable(_queue);

    await _loadAndPlayCurrentTrack();
  }

  /// Воспроизведение одиночного трека
  Future<void> playSingleTrack(Track track) async {
    final existingIndex = _queue.indexWhere((t) => t.id == track.id);
    if (existingIndex != -1) {
      _currentIndex = existingIndex;
    } else {
      _queue.insert(0, track);
      _currentIndex = 0;
      queueNotifier.value = List.unmodifiable(_queue);
    }
    await _loadAndPlayCurrentTrack();
  }

  Future<void> _loadAndPlayCurrentTrack() async {
    final track = currentTrack;
    if (track == null) return;

    final sessionId = ++_sessionCounter;
    currentTrackNotifier.value = track;

    final item = MediaItem(
      id: track.id.toString(),
      album: track.albumName ?? 'AuxBass',
      title: track.title,
      artist: track.artist,
      duration: Duration(seconds: track.duration),
      artUri: track.fullCoverUrl != null ? Uri.parse(track.fullCoverUrl!) : null,
    );

    // Сразу передаем информацию о треке в MediaItem шторки Android
    mediaItem.add(item);
    _broadcastState();

    try {
      // Активируем аудио-сессию
      final session = await AudioSession.instance;
      await session.setActive(true);

      // Запрашиваем актуальную ссылку на аудиопоток
      final streamUrl = await _apiService.getStreamUrl(track.id);

      // Если за время сетевого запроса пользователь уже переключил трек — прерываем
      if (sessionId != _sessionCounter) return;

      // Загружаем аудио-источник без вызова _player.stop(), чтобы не сбрасывать сервис
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(streamUrl),
          headers: const {
            'User-Agent': 'AuxBass/1.0.0 (Linux; Android 14; Mobile)',
          },
          tag: item,
        ),
        preload: true,
      );

      if (sessionId != _sessionCounter) return;

      await _player.play();

      // Фиксируем воспроизведение (скробблинг)
      _apiService.recordPlay(track.id);
    } catch (e) {
      debugPrint('[AudioPlayerHandler] Ошибка воспроизведения трека: $e');
      if (sessionId == _sessionCounter) {
        skipToNext();
      }
    }
  }

  @override
  Future<void> play() async {
    final session = await AudioSession.instance;
    await session.setActive(true);
    return _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_queue.isEmpty) return;

    if (_currentIndex + 1 < _queue.length) {
      _currentIndex++;
      await _loadAndPlayCurrentTrack();
    } else if (_loopMode == LoopMode.all) {
      _currentIndex = 0;
      await _loadAndPlayCurrentTrack();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_queue.isEmpty) return;

    // Если играем больше 3 секунд, то перемотка в начало
    if (_player.position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }

    if (_currentIndex > 0) {
      _currentIndex--;
      await _loadAndPlayCurrentTrack();
    } else if (_loopMode == LoopMode.all) {
      _currentIndex = _queue.length - 1;
      await _loadAndPlayCurrentTrack();
    }
  }

  /// Переключение режима перемешивания (Shuffle)
  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    if (_isShuffle && _queue.isNotEmpty) {
      final current = currentTrack;
      _queue.shuffle();
      if (current != null) {
        _queue.removeWhere((t) => t.id == current.id);
        _queue.insert(0, current);
        _currentIndex = 0;
      }
    }
    queueNotifier.value = List.unmodifiable(_queue);
  }

  /// Переключение режима повтора (Выкл -> Все -> Один)
  void toggleLoopMode() {
    switch (_loopMode) {
      case LoopMode.off:
        _loopMode = LoopMode.all;
        break;
      case LoopMode.all:
        _loopMode = LoopMode.one;
        break;
      case LoopMode.one:
        _loopMode = LoopMode.off;
        break;
    }
  }
}
