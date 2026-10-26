import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import 'api_service.dart';

/// Глобальный обработчик воспроизведения аудио с поддержкой системных уведомлений
class AudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final ApiService _apiService = ApiService();

  List<Track> _queue = [];
  int _currentIndex = -1;
  bool _isShuffle = false;
  LoopMode _loopMode = LoopMode.off;

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
    _player.playbackEventStream.listen((PlaybackEvent event) {
      final playing = _player.playing;
      playbackState.add(
        playbackState.value.copyWith(
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
          processingState: const {
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          }[_player.processingState]!,
          playing: playing,
          updatePosition: _player.position,
          bufferedPosition: _player.bufferedPosition,
          speed: _player.speed,
          queueIndex: _currentIndex,
        ),
      );
    });

    // Автоматический переход к следующему треку при окончании
    _player.playerStateStream.listen((state) {
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

    currentTrackNotifier.value = track;

    // Обновляем информацию в шторке уведомлений и на экране блокировки Android
    mediaItem.add(
      MediaItem(
        id: track.id.toString(),
        album: track.albumName ?? 'AuxBass',
        title: track.title,
        artist: track.artist,
        duration: Duration(seconds: track.duration),
        artUri: track.fullCoverUrl != null ? Uri.parse(track.fullCoverUrl!) : null,
      ),
    );

    try {
      // Запрашиваем актуальную ссылку на аудиопоток
      final streamUrl = await _apiService.getStreamUrl(track.id);

      await _player.stop();
      await _player.setUrl(streamUrl);
      await _player.play();

      // Фиксируем воспроизведение (скробблинг)
      _apiService.recordPlay(track.id);
    } catch (e) {
      debugPrint('[AudioPlayerHandler] Ошибка воспроизведения трека: $e');
      // При ошибке переходим к следующему треку в очереди
      skipToNext();
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
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
