import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import 'models/readalong_document.dart';
import 'parser.dart';

enum ButtonState { playingLoading, pausedLoading, completed, paused, playing }

/// Owns the ReadAlong document and audio state, and exposes playback commands.
class Manager extends ChangeNotifier {
  Manager({
    required String? xml,
    required String? xmlAsset,
    required AudioSource? audioSource,
    ReadalongParser? parser,
    AudioPlayer? audioPlayer,
    this.imagesFolder,
  }) : assert((xml == null) != (xmlAsset == null)),
       _xml = xml,
       _xmlAsset = xmlAsset,
       _audioSource = audioSource, // ignore: prefer_initializing_formals
       _parser = parser ?? ReadalongParser(),
       _ownsAudioPlayer = audioPlayer == null,
       _player = audioPlayer ?? AudioPlayer();

  String? _xml;
  String? _xmlAsset;
  AudioSource? _audioSource;
  final ReadalongParser _parser;
  final bool _ownsAudioPlayer;
  final AudioPlayer _player;
  final String? imagesFolder;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;

  ReadAlongDocument? _document;
  Object? _xmlError;
  Object? _audioError;
  Duration _position = Duration.zero;
  Duration? _seekPreviewPosition;
  Duration? _duration;
  String? _activeWordId;
  bool _isAudioLoading = false;
  bool _isPlaying = false;
  bool _isCompleted = false;
  bool _autoplay = false;
  int? _pausedAtPageIndex;
  Duration? _wordPlaybackEnd;
  String? _wordPlaybackHighlightId;
  bool _isFinishingWordPlayback = false;
  bool _isSeeking = false;
  int _wordPlaybackGeneration = 0;
  double _speed = 1;
  final ValueNotifier<ButtonState> _buttonState = ValueNotifier(
    ButtonState.paused,
  );

  ReadAlongDocument? get document => _document;
  Object? get xmlError => _xmlError;
  Object? get audioError => _audioError;
  Duration get position => _position;
  Duration get displayPosition => _seekPreviewPosition ?? _position;
  Duration? get duration => _duration;
  String? get activeWordId => _activeWordId;
  bool get isAudioLoading => _isAudioLoading;
  bool get isPlaying => _isPlaying;
  bool get isSeeking => _isSeeking;
  bool get isCompleted => _isCompleted;
  bool get autoplay => !_autoplay;
  double get speed => _speed;
  ValueListenable<ButtonState> get buttonState => _buttonState;

  bool _hasConfiguredAudio = false;
  bool _disposed = false;
  int _audioConfiguration = 0;
  int _documentConfiguration = 0;

  Future<void> initialize() async {
    _positionSubscription = _player.positionStream.listen(
      _updatePosition,
      onError: _handleAudioError,
    );
    _playerStateSubscription = _player.playerStateStream.listen(
      _updatePlayerState,
      onError: _handleAudioError,
    );
    await Future.wait([_loadDocument(), _configureAudio()]);
  }

  /// Updates the sources when the owning widget receives new inputs.
  Future<void> updateSources({
    required String? xml,
    required String? xmlAsset,
    required AudioSource? audioSource,
  }) async {
    final documentChanged = _xml != xml || _xmlAsset != xmlAsset;
    final audioChanged = _audioSource != audioSource;
    _xml = xml;
    _xmlAsset = xmlAsset;
    _audioSource = audioSource;

    final updates = <Future<void>>[];
    if (documentChanged) updates.add(_loadDocument());
    if (audioChanged) updates.add(_configureAudio());
    await Future.wait(updates);
  }

  Future<void> _loadDocument() async {
    final configuration = ++_documentConfiguration;
    _clearWordPlaybackEnd();
    _document = null;
    _xmlError = null;
    _activeWordId = null;
    notifyListeners();

    try {
      final source = _xml ?? await rootBundle.loadString(_xmlAsset!);
      if (_disposed || configuration != _documentConfiguration) return;
      _document = _parser.parseXml(source);
      _xmlError = null;
      _updateActiveWord(_position);
    } catch (error) {
      if (_disposed || configuration != _documentConfiguration) return;
      _xmlError = error;
    }
    notifyListeners();
  }

  Future<void> _configureAudio() async {
    final configuration = ++_audioConfiguration;
    _clearWordPlaybackEnd();
    final source = _audioSource;
    _audioError = null;

    if (source == null) {
      Object? stopError;
      if (_hasConfiguredAudio) {
        try {
          await _player.stop();
        } catch (error) {
          stopError = error;
        }
      }
      if (_disposed || configuration != _audioConfiguration) return;
      _hasConfiguredAudio = false;
      _audioError = stopError;
      _isAudioLoading = false;
      _isPlaying = false;
      _isCompleted = false;
      _duration = null;
      _position = Duration.zero;
      _activeWordId = null;
      _setPlayerState(ButtonState.paused);
      notifyListeners();
      return;
    }

    _isAudioLoading = true;
    _duration = null;
    _setPlayerState(
      _isPlaying ? ButtonState.playingLoading : ButtonState.pausedLoading,
    );
    notifyListeners();
    try {
      final loadedDuration = await _player.setAudioSource(source);
      if (_disposed || configuration != _audioConfiguration) return;
      _hasConfiguredAudio = true;
      _duration = loadedDuration;
      _position = Duration.zero;
      _isAudioLoading = false;
      _isCompleted = false;
      _setPlayerState(ButtonState.paused);
      _updateActiveWord(_position);
      notifyListeners();
    } catch (error) {
      if (_disposed || configuration != _audioConfiguration) return;
      _audioError = error;
      _isAudioLoading = false;
      _setPlayerState(ButtonState.paused);
      notifyListeners();
    }
  }

  void _updatePlayerState(PlayerState state) {
    if (_disposed) return;
    _isAudioLoading =
        state.processingState == ProcessingState.loading ||
        state.processingState == ProcessingState.buffering;
    _isPlaying = state.playing;
    _isCompleted = state.processingState == ProcessingState.completed;
    _setPlayerState(_toReadAlongPlayerState(state));
    if (_isCompleted && _duration != null) {
      _position = _duration!;
      _updateActiveWord(_position);
    }
    _speed = _player.speed;
    notifyListeners();
  }

  ButtonState _toReadAlongPlayerState(PlayerState state) {
    if (_isSeeking) return ButtonState.paused;
    if (state.processingState == ProcessingState.loading ||
        state.processingState == ProcessingState.buffering) {
      return state.playing
          ? ButtonState.playingLoading
          : ButtonState.pausedLoading;
    }
    if (state.processingState == ProcessingState.completed) {
      return ButtonState.completed;
    }
    return state.playing ? ButtonState.playing : ButtonState.paused;
  }

  void _setPlayerState(ButtonState state) {
    if (!_disposed && _buttonState.value != state) {
      _buttonState.value = state;
    }
  }

  void _updatePosition(Duration newPosition) {
    if (_disposed || _isSeeking) return;
    final wordEnd = _wordPlaybackEnd;
    if (wordEnd != null && newPosition >= wordEnd) {
      _position = wordEnd;
      _updateActiveWord(wordEnd);
      if (!_isFinishingWordPlayback) {
        _isFinishingWordPlayback = true;
        unawaited(_finishWordPlayback(wordEnd, _wordPlaybackGeneration));
      }
      notifyListeners();
      return;
    }
    final previousPosition = _position;
    if (_pauseAtPageEnd(previousPosition, newPosition)) {
      notifyListeners();
      return;
    }
    _position = newPosition;
    _updateActiveWord(newPosition);
    notifyListeners();
  }

  bool _pauseAtPageEnd(Duration previousPosition, Duration position) {
    if (_pausedAtPageIndex != null) return true;
    if (!_autoplay || !_isPlaying || _wordPlaybackEnd != null) {
      return false;
    }

    final boundary = previousPosition == position
        ? _pageBoundaryAt(position)
        : _pageBoundaryCrossed(previousPosition, position);
    if (boundary == null || position < boundary.end) return false;
    if (_nextAlignedPage(boundary.pageIndex) == null) return false;

    _pausedAtPageIndex = boundary.pageIndex;
    _position = boundary.end;
    _activeWordId = boundary.wordId;
    unawaited(_finishPagePlayback(boundary.end, _wordPlaybackGeneration));
    return true;
  }

  ({int pageIndex, Duration end, String wordId})? _pageBoundaryCrossed(
    Duration previousPosition,
    Duration position,
  ) {
    final pages = _document?.pages;
    if (pages == null) return null;

    for (final (pageIndex, page) in pages.indexed) {
      final range = _pagePlaybackRange(pageIndex, page);
      if (range != null &&
          previousPosition < range.end &&
          position >= range.end) {
        return (
          pageIndex: pageIndex,
          end: range.end,
          wordId: range.lastWord.id,
        );
      }
    }
    return null;
  }

  ({int pageIndex, Duration start, Duration end, ReadAlongWord lastWord})?
  _pagePlaybackRange(int pageIndex, ReadAlongPage page) {
    final words = page.paragraphs
        .expand((paragraph) => paragraph.sentences)
        .expand((sentence) => sentence.segments)
        .whereType<ReadAlongWord>()
        .where((word) => word.isAligned)
        .toList();
    if (words.isEmpty) return null;

    final starts = words.map((word) => word.start!).toList()..sort();
    final lastWord = words.reduce((latest, word) {
      final wordEnd = word.start! + word.duration!;
      final latestEnd = latest.start! + latest.duration!;
      return wordEnd > latestEnd ? word : latest;
    });
    return (
      pageIndex: pageIndex,
      start: starts.first,
      end: lastWord.start! + lastWord.duration!,
      lastWord: lastWord,
    );
  }

  ({int pageIndex, Duration end, String wordId})? _pageBoundaryAt(
    Duration position,
  ) {
    final pages = _document?.pages;
    if (pages == null) return null;

    final pageRanges =
        <
          ({
            int pageIndex,
            Duration start,
            Duration end,
            ReadAlongWord lastWord,
          })
        >[];
    for (final (pageIndex, page) in pages.indexed) {
      final range = _pagePlaybackRange(pageIndex, page);
      if (range != null) pageRanges.add(range);
    }

    if (pageRanges.isEmpty) return null;
    var currentPage = pageRanges.first;
    for (final range in pageRanges.skip(1)) {
      if (range.start > position) break;
      currentPage = range;
    }
    return (
      pageIndex: currentPage.pageIndex,
      end: currentPage.end,
      wordId: currentPage.lastWord.id,
    );
  }

  Future<void> _finishPagePlayback(Duration end, int generation) async {
    try {
      await _player.pause();
      if (_disposed || generation != _wordPlaybackGeneration) return;
      await _player.seek(end);
      if (_disposed || generation != _wordPlaybackGeneration) return;
      _position = end;
      final pageIndex = _pausedAtPageIndex;
      final pages = _document?.pages;
      if (pageIndex != null && pages != null && pageIndex < pages.length) {
        final lastWord = _pagePlaybackRange(
          pageIndex,
          pages[pageIndex],
        )?.lastWord;
        if (lastWord != null) _activeWordId = lastWord.id;
      }
      notifyListeners();
    } catch (error) {
      if (generation == _wordPlaybackGeneration) {
        _pausedAtPageIndex = null;
        _handleAudioError(error);
      }
    }
  }

  void togglePagePlaybackMode() {
    _autoplay = !_autoplay;
    if (!_autoplay) {
      _pausedAtPageIndex = null;
    } else {
      _pauseAtPageEnd(_position, _position);
    }
    notifyListeners();
  }

  Future<void> _finishWordPlayback(Duration end, int generation) async {
    try {
      await _player.pause();
      if (_disposed || generation != _wordPlaybackGeneration) return;
      await _player.seek(end);
      if (_disposed || generation != _wordPlaybackGeneration) return;
      _position = end;
      _updateActiveWord(end);
      _wordPlaybackEnd = null;
      _isFinishingWordPlayback = false;
      notifyListeners();
    } catch (error) {
      if (generation == _wordPlaybackGeneration) {
        _wordPlaybackEnd = null;
        _isFinishingWordPlayback = false;
        _handleAudioError(error);
      }
    }
  }

  void _clearWordPlaybackEnd() {
    _wordPlaybackGeneration++;
    _pausedAtPageIndex = null;
    _wordPlaybackEnd = null;
    _wordPlaybackHighlightId = null;
    _isFinishingWordPlayback = false;
  }

  void _updateActiveWord(Duration at) {
    final highlightedWordId = _wordPlaybackHighlightId;
    if (highlightedWordId != null) {
      _activeWordId = highlightedWordId;
      return;
    }

    _activeWordId = null;
    for (final word in _document?.words ?? const <ReadAlongWord>[]) {
      if (!word.isAligned) continue;
      final start = word.start!;
      if (at >= start && at < start + word.duration!) {
        _activeWordId = word.id;
      }
    }
  }

  void _handleAudioError(Object error, [StackTrace? stackTrace]) {
    if (_disposed) return;
    _audioError = error;
    _isAudioLoading = false;
    notifyListeners();
  }

  Future<void> play() async {
    if (_audioSource == null || _isAudioLoading) return;
    final pausedPageIndex = _pausedAtPageIndex;
    _pausedAtPageIndex = null;
    _clearWordPlaybackEnd();
    _updateActiveWord(_position);
    try {
      if (pausedPageIndex != null) {
        final nextPage = _nextAlignedPage(pausedPageIndex);
        if (nextPage != null) {
          final nextPageStart = nextPage.start!;
          await _player.seek(nextPageStart);
          _position = nextPageStart;
          _updateActiveWord(_position);
        }
      } else if (_isCompleted ||
          (_duration != null && _position >= _duration!)) {
        await _player.seek(Duration.zero);
      }
      await _player.play();
    } catch (error) {
      _handleAudioError(error);
    }
  }

  Future<void> pause() async {
    _clearWordPlaybackEnd();
    _updateActiveWord(_position);
    try {
      await _player.pause();
    } catch (error) {
      _handleAudioError(error);
    }
  }

  Future<void> stop() async {
    _clearWordPlaybackEnd();
    try {
      await _player.stop();
      _position = Duration.zero;
      _updateActiveWord(_position);
      notifyListeners();
    } catch (error) {
      _handleAudioError(error);
    }
  }

  Future<void> replay() async {
    _pausedAtPageIndex = null;
    _clearWordPlaybackEnd();
    _updateActiveWord(Duration.zero);
    try {
      await _player.seek(Duration.zero);
      await _player.play();
    } catch (error) {
      _handleAudioError(error);
    }
  }

  Future<void> beginSeek() async {
    if (_isSeeking) return;
    _isSeeking = true;
    _seekPreviewPosition = _position;
    _clearWordPlaybackEnd();
    _pausedAtPageIndex = null;
    notifyListeners();
    if (!_isPlaying) return;

    try {
      await _player.pause();
    } catch (error) {
      _isSeeking = false;
      _seekPreviewPosition = null;
      _handleAudioError(error);
    }
  }

  void updateSeekPreviewMilliseconds(double milliseconds) {
    if (!_isSeeking) return;
    final target = Duration(milliseconds: milliseconds.round());
    _seekPreviewPosition = target;
    _updateActiveWord(target);
    notifyListeners();
  }

  Future<void> endSeek(double milliseconds) async {
    if (!_isSeeking) return;
    final target = Duration(milliseconds: milliseconds.round());
    _seekPreviewPosition = target;
    _updateActiveWord(target);
    try {
      await _player.seek(target);
      _position = target;
      _isSeeking = false;
      _seekPreviewPosition = null;
      _updateActiveWord(target);
      notifyListeners();
    } catch (error) {
      _isSeeking = false;
      _seekPreviewPosition = null;
      _updateActiveWord(_position);
      _handleAudioError(error);
    }
  }

  Future<void> seek(Duration target) async {
    if (_isAudioLoading) return;
    _pausedAtPageIndex = null;
    _clearWordPlaybackEnd();
    _updateActiveWord(target);
    try {
      await _player.seek(target);
    } catch (error) {
      _handleAudioError(error);
    }
  }

  Future<void> seekMilliseconds(double milliseconds) {
    return seek(Duration(milliseconds: milliseconds.round()));
  }

  Future<void> playWord(ReadAlongWord word) async {
    if (!word.isAligned || _audioSource == null || _isAudioLoading) return;
    // A word tap while playing seeks playback without turning it into a
    // one-word preview; from pause, playback is bounded to the selected word.
    final continuePlayback = _isPlaying;
    _pausedAtPageIndex = null;
    _clearWordPlaybackEnd();
    final generation = _wordPlaybackGeneration;
    final end = word.start! + word.duration!;
    if (!continuePlayback) {
      _wordPlaybackHighlightId = word.id;
      _wordPlaybackEnd = end;
    }
    _activeWordId = word.id;
    notifyListeners();
    try {
      await _player.seek(word.start);
      if (_disposed || generation != _wordPlaybackGeneration) return;
      _position = word.start!;
      _updateActiveWord(_position);
      await _player.play();
    } catch (error) {
      if (generation == _wordPlaybackGeneration) {
        _clearWordPlaybackEnd();
        _handleAudioError(error);
      }
    }
  }

  ReadAlongWord? _nextAlignedPage(int pageIndex) {
    final pages = _document?.pages;
    if (pages == null) return null;
    for (final page in pages.skip(pageIndex + 1)) {
      final firstWord = page.paragraphs
          .expand((paragraph) => paragraph.sentences)
          .expand((sentence) => sentence.segments)
          .whereType<ReadAlongWord>()
          .where((word) => word.isAligned)
          .fold<ReadAlongWord?>(
            null,
            (earliest, word) =>
                earliest == null || word.start! < earliest.start!
                ? word
                : earliest,
          );
      if (firstWord != null) return firstWord;
    }
    return null;
  }

  String getImageAsset(String imageUrl) {
    final folder = imagesFolder?.trim();
    final imagePath = imageUrl.replaceFirst(RegExp(r'^(?:\./|/)+'), '');
    if (folder == null || folder.isEmpty) return imagePath;

    return '${folder.replaceFirst(RegExp(r'/+$'), '')}/$imagePath';
  }

  Future<void> playWordById(String id) async {
    final word = _document?.words.where((item) => item.id == id).firstOrNull;
    if (word != null) await playWord(word);
  }

  Future<void> setSpeed(double value) async {
    try {
      await _player.setSpeed(value);
      _speed = _player.speed;
      notifyListeners();
    } catch (error) {
      _handleAudioError(error);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_positionSubscription?.cancel());
    unawaited(_playerStateSubscription?.cancel());
    _buttonState.dispose();
    if (_ownsAudioPlayer) unawaited(_player.dispose());
    super.dispose();
  }
}
