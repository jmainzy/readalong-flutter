import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState, ProcessingState;

import '../models/playback_controller.dart';

enum ButtonState { playingLoading, pausedLoading, completed, paused, playing }

/// Owns the audio player or external playback controller and all its commands.
class AudioManager extends ChangeNotifier {
  AudioManager({
    AudioSource? audioSource,
    PlaybackController? playbackController,
    AudioPlayer? audioPlayer,
  }) : assert(audioSource == null || playbackController == null),
       _audioSource = audioSource,
       _hasExternalPlaybackController = playbackController != null {
    _player = audioPlayer ?? AudioPlayer();
    _ownsAudioPlayer = audioPlayer == null && playbackController == null;
    _playbackController =
        playbackController ?? _JustAudioPlaybackController(_player);
    _position = _playbackController.position;
    _duration = _playbackController.duration;
    _speed = _playbackController.speed;
    _updatePlaybackState(_playbackController.state);
    _bindPlaybackController();
    if (!_hasExternalPlaybackController) unawaited(_configureAudioSource());
  }

  late final bool _ownsAudioPlayer;
  late final AudioPlayer _player;
  late PlaybackController _playbackController;
  AudioSource? _audioSource;
  bool _hasExternalPlaybackController;
  bool _hasConfiguredAudio = false;
  bool _disposed = false;
  int _configuration = 0;
  int _operationGeneration = 0;
  int? _nextPlayPositionMilliseconds;
  Duration? _wordPlaybackEnd;
  Duration? _seekPreviewPosition;
  Duration _position = Duration.zero;
  Duration? _duration;
  double _speed = 1;
  Object? _audioError;
  bool _isSeeking = false;
  late final ValueNotifier<ButtonState> _buttonState = ValueNotifier(
    ButtonState.paused,
  );
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;

  Duration get position => _position;
  Duration get displayPosition => _seekPreviewPosition ?? _position;
  Duration? get duration => _duration;
  double get speed => _speed;
  Object? get audioError => _audioError;
  bool get isPlaying => _playbackController.state.playing;
  bool get isAudioLoading =>
      _playbackController.state.processingState == ProcessingState.loading ||
      _playbackController.state.processingState == ProcessingState.buffering;
  bool get isSeeking => _isSeeking;
  bool get isCompleted =>
      _playbackController.state.processingState == ProcessingState.completed;
  bool get canPlay => _hasExternalPlaybackController || _audioSource != null;
  ValueListenable<ButtonState> get buttonState => _buttonState;
  Stream<Duration> get positionStream => _playbackController.positionStream;

  Future<void> updateSources({
    required AudioSource? audioSource,
    required PlaybackController? playbackController,
  }) async {
    final controllerChanged =
        _playbackController != playbackController &&
        (playbackController != null || _hasExternalPlaybackController);
    final sourceChanged = _audioSource != audioSource;
    _audioSource = audioSource;
    if (controllerChanged) {
      _hasExternalPlaybackController = playbackController != null;
      _playbackController =
          playbackController ?? _JustAudioPlaybackController(_player);
      await _cancelPlaybackSubscriptions();
      _bindPlaybackController();
    }

    if (controllerChanged || sourceChanged) {
      _operationGeneration++;
      _wordPlaybackEnd = null;
      _nextPlayPositionMilliseconds = null;
      _isSeeking = false;
      _seekPreviewPosition = null;
      if (_hasExternalPlaybackController) {
        _hasConfiguredAudio = true;
        _syncFromController();
        notifyListeners();
      } else {
        await _configureAudioSource();
      }
    }
  }

  Future<void> _configureAudioSource() async {
    final configuration = ++_configuration;
    final source = _audioSource;
    _audioError = null;

    if (source == null) {
      Object? stopError;
      if (_hasConfiguredAudio) {
        try {
          await _playbackController.stop();
        } catch (error) {
          stopError = error;
        }
      }
      if (_disposed || configuration != _configuration) return;
      _hasConfiguredAudio = false;
      _audioError = stopError;
      _duration = null;
      _position = Duration.zero;
      _setButtonState(ButtonState.paused);
      notifyListeners();
      return;
    }

    _setButtonState(
      isPlaying ? ButtonState.playingLoading : ButtonState.pausedLoading,
    );
    notifyListeners();
    try {
      final duration = await _player.setAudioSource(source);
      if (_disposed || configuration != _configuration) return;
      _hasConfiguredAudio = true;
      _duration = duration;
      _position = Duration.zero;
      _setButtonState(ButtonState.paused);
      notifyListeners();
    } catch (error) {
      if (_disposed || configuration != _configuration) return;
      _audioError = error;
      _setButtonState(ButtonState.paused);
      notifyListeners();
    }
  }

  void _syncFromController() {
    _duration = _playbackController.duration;
    _position = _playbackController.position;
    _speed = _playbackController.speed;
    _updatePlaybackState(_playbackController.state);
  }

  void _bindPlaybackController() {
    _positionSubscription = _playbackController.positionStream.listen(
      _updatePosition,
      onError: _handleAudioError,
    );
    _durationSubscription = _playbackController.durationStream.listen(
      _updateDuration,
      onError: _handleAudioError,
    );
    _playerStateSubscription = _playbackController.stateStream.listen(
      _updatePlaybackState,
      onError: _handleAudioError,
    );
  }

  Future<void> _cancelPlaybackSubscriptions() async {
    await _positionSubscription?.cancel();
    await _durationSubscription?.cancel();
    await _playerStateSubscription?.cancel();
    _positionSubscription = null;
    _durationSubscription = null;
    _playerStateSubscription = null;
  }

  void _updatePosition(Duration position) {
    if (_disposed || _isSeeking) return;
    final end = _wordPlaybackEnd;
    if (end != null && position >= end) {
      _position = end;
      unawaited(_finishWordPlayback(end, _operationGeneration));
      notifyListeners();
      return;
    }
    _position = position;
    notifyListeners();
  }

  void _updateDuration(Duration? duration) {
    if (_disposed) return;
    _duration = duration;
    if (duration != null && _position > duration) _position = duration;
    notifyListeners();
  }

  void _updatePlaybackState(PlayerState state) {
    if (_disposed) return;
    final loading =
        state.processingState == ProcessingState.loading ||
        state.processingState == ProcessingState.buffering;
    _setButtonState(
      _isSeeking
          ? ButtonState.paused
          : loading
          ? (state.playing
                ? ButtonState.playingLoading
                : ButtonState.pausedLoading)
          : state.processingState == ProcessingState.completed
          ? ButtonState.completed
          : state.playing
          ? ButtonState.playing
          : ButtonState.paused,
    );
    if (state.processingState == ProcessingState.completed &&
        _duration != null) {
      _position = _duration!;
    }
    _speed = _playbackController.speed;
    notifyListeners();
  }

  void _setButtonState(ButtonState state) {
    if (!_disposed && _buttonState.value != state) _buttonState.value = state;
  }

  void _handleAudioError(Object error, [StackTrace? stackTrace]) {
    if (_disposed) return;
    _audioError = error;
    notifyListeners();
  }

  /// Makes the next paused [play] request start at [position].
  void preparePlaybackFromPosition(Duration position) {
    if (!isPlaying) _nextPlayPositionMilliseconds = position.inMilliseconds;
  }

  Future<void> play() async {
    if (!canPlay || isAudioLoading) return;
    final generation = ++_operationGeneration;
    final requestedStart = _nextPlayPositionMilliseconds;
    _nextPlayPositionMilliseconds = null;
    _wordPlaybackEnd = null;
    try {
      if (requestedStart != null) {
        final start = Duration(milliseconds: requestedStart);
        await _playbackController.seek(start);
        if (_disposed || generation != _operationGeneration) return;
        _position = start;
      } else if (isCompleted ||
          (_duration != null && _position >= _duration!)) {
        await _playbackController.seek(Duration.zero);
        if (_disposed || generation != _operationGeneration) return;
        _position = Duration.zero;
      }
      await _playbackController.play();
    } catch (error) {
      _handleAudioError(error);
    }
  }

  Future<void> pause() async {
    _operationGeneration++;
    _wordPlaybackEnd = null;
    _nextPlayPositionMilliseconds = null;
    try {
      await _playbackController.pause();
    } catch (error) {
      _handleAudioError(error);
    }
  }

  Future<void> pauseAt(Duration position, {Duration? resumePosition}) async {
    final generation = ++_operationGeneration;
    _wordPlaybackEnd = null;
    _nextPlayPositionMilliseconds = resumePosition?.inMilliseconds;
    try {
      await _playbackController.pause();
      if (_disposed || generation != _operationGeneration) return;
      await _playbackController.seek(position);
      if (_disposed || generation != _operationGeneration) return;
      _position = position;
      notifyListeners();
    } catch (error) {
      _handleAudioError(error);
    }
  }

  Future<void> stop() async {
    _operationGeneration++;
    _wordPlaybackEnd = null;
    _nextPlayPositionMilliseconds = null;
    try {
      await _playbackController.stop();
      _position = Duration.zero;
      notifyListeners();
    } catch (error) {
      _handleAudioError(error);
    }
  }

  Future<void> replay() async {
    final generation = ++_operationGeneration;
    _wordPlaybackEnd = null;
    try {
      await _playbackController.pause();
      if (_disposed || generation != _operationGeneration) return;
      await _playbackController.seek(Duration.zero);
      if (_disposed || generation != _operationGeneration) return;
      _position = Duration.zero;
      await _playbackController.play();
    } catch (error) {
      _handleAudioError(error);
    }
  }

  Future<void> beginSeek() async {
    if (_isSeeking) return;
    _operationGeneration++;
    _wordPlaybackEnd = null;
    _nextPlayPositionMilliseconds = null;
    _isSeeking = true;
    _seekPreviewPosition = _position;
    notifyListeners();
    if (!isPlaying) return;
    try {
      await _playbackController.pause();
    } catch (error) {
      _isSeeking = false;
      _seekPreviewPosition = null;
      _handleAudioError(error);
    }
  }

  void updateSeekPreviewMilliseconds(double milliseconds) {
    if (!_isSeeking) return;
    _seekPreviewPosition = Duration(milliseconds: milliseconds.round());
    notifyListeners();
  }

  Future<void> endSeek(double milliseconds) async {
    if (!_isSeeking) return;
    final target = Duration(milliseconds: milliseconds.round());
    final generation = _operationGeneration;
    _seekPreviewPosition = target;
    notifyListeners();
    try {
      await _playbackController.seek(target);
      if (_disposed || generation != _operationGeneration) return;
      _position = target;
      _isSeeking = false;
      _seekPreviewPosition = null;
      notifyListeners();
    } catch (error) {
      _isSeeking = false;
      _seekPreviewPosition = null;
      _handleAudioError(error);
    }
  }

  Future<void> seek(Duration target) async {
    if (isAudioLoading) return;
    final generation = ++_operationGeneration;
    _nextPlayPositionMilliseconds = null;
    _wordPlaybackEnd = null;
    try {
      await _playbackController.seek(target);
      if (_disposed || generation != _operationGeneration) return;
      _position = target;
      notifyListeners();
    } catch (error) {
      _handleAudioError(error);
    }
  }

  Future<void> seekMilliseconds(double milliseconds) =>
      seek(Duration(milliseconds: milliseconds.round()));

  Future<void> playWord(Duration start, Duration duration) async {
    if (!canPlay || isAudioLoading) return;
    final generation = ++_operationGeneration;
    _nextPlayPositionMilliseconds = null;
    int buffer = 0;
    if (kIsWeb && !_hasExternalPlaybackController) {
      // add a buffer for web because the playback is weird.
      buffer = 200;
      start = Duration(milliseconds: max(start.inMilliseconds - buffer, 0));
      duration = Duration(milliseconds: duration.inMilliseconds + buffer);
    }

    _wordPlaybackEnd = isPlaying ? null : start + duration;

    try {
      await _playbackController.seek(start);
      if (_disposed || generation != _operationGeneration) return;
      _position = start + Duration(milliseconds: buffer);
      await _playbackController.play();
    } catch (error) {
      if (generation == _operationGeneration) {
        _wordPlaybackEnd = null;
        _handleAudioError(error);
      }
    }
  }

  Future<void> _finishWordPlayback(Duration end, int generation) async {
    int buffer = 0;
    if (kIsWeb && !_hasExternalPlaybackController) {
      buffer = 200;
    }
    try {
      await _playbackController.pause();
      if (_disposed || generation != _operationGeneration) return;
      await _playbackController.seek(end - Duration(milliseconds: buffer));
      if (_disposed || generation != _operationGeneration) return;
      _position = end - Duration(milliseconds: buffer);
      _wordPlaybackEnd = null;
      notifyListeners();
    } catch (error) {
      if (generation == _operationGeneration) {
        _wordPlaybackEnd = null;
        _handleAudioError(error);
      }
    }
  }

  Future<void> setSpeed(double value) async {
    try {
      await _playbackController.setSpeed(value);
      _speed = _playbackController.speed;
      notifyListeners();
    } catch (error) {
      _handleAudioError(error);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_cancelPlaybackSubscriptions());
    _buttonState.dispose();
    if (_ownsAudioPlayer) unawaited(_player.dispose());
    super.dispose();
  }
}

class _JustAudioPlaybackController implements PlaybackController {
  _JustAudioPlaybackController(this._player);

  final AudioPlayer _player;

  @override
  Duration get position => _player.position;

  @override
  Duration? get duration => _player.duration;

  @override
  double get speed => _player.speed;

  @override
  PlayerState get state => PlayerState.fromJustAudio(_player.playerState);

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Stream<PlayerState> get stateStream =>
      _player.playerStateStream.map(PlayerState.fromJustAudio);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);
}
