import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/readalong_document.dart';
import 'audio_manager.dart';
import '../parser.dart';

/// Owns document parsing, word highlighting, and page-timing decisions.
class TextManager extends ChangeNotifier {
  TextManager({
    required String? xml,
    required String? xmlAsset,
    required this.audioManager,
    ReadalongParser? parser,
    this.imagesFolder,
  }) : assert((xml == null) != (xmlAsset == null)),
       _xml = xml,
       _xmlAsset = xmlAsset,
       _parser = parser ?? ReadalongParser() {
    audioManager.addListener(_handleAudioChanged);
  }

  final AudioManager audioManager;
  final ReadalongParser _parser;
  final String? imagesFolder;
  String? _xml;
  String? _xmlAsset;
  ReadAlongDocument? _document;
  Object? _xmlError;
  String? _activeWordId;
  String? _manuallyHighlightedWordId;
  Duration _lastPosition = Duration.zero;
  bool _pauseAtPageEnds = false;
  bool _handlingPageBoundary = false;
  bool _disposed = false;
  int _documentConfiguration = 0;

  ReadAlongDocument? get document => _document;
  Object? get xmlError => _xmlError;
  String? get activeWordId => _activeWordId;
  bool get autoplay => !_pauseAtPageEnds;

  Future<void> initialize() => _loadDocument();

  Future<void> updateSources({
    required String? xml,
    required String? xmlAsset,
  }) async {
    if (_xml == xml && _xmlAsset == xmlAsset) return;
    _xml = xml;
    _xmlAsset = xmlAsset;
    await _loadDocument();
  }

  Future<void> _loadDocument() async {
    final configuration = ++_documentConfiguration;
    _lastPosition = audioManager.displayPosition;
    _document = null;
    _xmlError = null;
    _activeWordId = null;
    _manuallyHighlightedWordId = null;
    notifyListeners();
    try {
      final source = _xml ?? await rootBundle.loadString(_xmlAsset!);
      if (_disposed || configuration != _documentConfiguration) return;
      _document = _parser.parseXml(source);
      _xmlError = null;
      _lastPosition = audioManager.displayPosition;
      _updateActiveWord(audioManager.displayPosition);
    } catch (error) {
      if (_disposed || configuration != _documentConfiguration) return;
      _xmlError = error;
    }
    notifyListeners();
  }

  void _handleAudioChanged() {
    if (_disposed) return;
    final position = audioManager.displayPosition;
    final manuallyHighlightedWord = _manuallyHighlightedWordId == null
        ? null
        : _document?.words
              .where((word) => word.id == _manuallyHighlightedWordId)
              .firstOrNull;
    if (audioManager.isSeeking ||
        (manuallyHighlightedWord != null &&
            (!manuallyHighlightedWord.isAligned ||
                position < manuallyHighlightedWord.start! ||
                position >=
                    manuallyHighlightedWord.start! +
                        manuallyHighlightedWord.duration!))) {
      _manuallyHighlightedWordId = null;
    }
    _updateActiveWord(position);
    if (!_handlingPageBoundary &&
        _pauseAtPageEnds &&
        audioManager.isPlaying &&
        !audioManager.isSeeking) {
      final boundary = _pageBoundaryCrossed(_lastPosition, position);
      final nextPage = boundary == null
          ? null
          : _nextAlignedPage(boundary.pageIndex);
      if (boundary != null &&
          position >= boundary.position &&
          nextPage != null) {
        _handlingPageBoundary = true;
        unawaited(
          audioManager
              .pauseAt(boundary.position, resumePosition: nextPage.start!)
              .whenComplete(() => _handlingPageBoundary = false),
        );
      }
    }
    _lastPosition = position;
    notifyListeners();
  }

  void _updateActiveWord(Duration position) {
    if (_manuallyHighlightedWordId != null) {
      _activeWordId = _manuallyHighlightedWordId;
      return;
    }
    _activeWordId = _nearestWordForPosition(position)?.id;
  }

  List<({int pageIndex, Duration start, Duration end, ReadAlongWord lastWord})>
  _alignedPageRanges() {
    final pages = _document?.pages;
    if (pages == null) return [];
    final ranges =
        <
          ({
            int pageIndex,
            Duration start,
            Duration end,
            ReadAlongWord lastWord,
          })
        >[];
    for (final (pageIndex, page) in pages.indexed) {
      final words = page.paragraphs
          .expand((paragraph) => paragraph.sentences)
          .expand((sentence) => sentence.segments)
          .whereType<ReadAlongWord>()
          .where((word) => word.isAligned)
          .toList();
      if (words.isEmpty) continue;
      final starts = words.map((word) => word.start!).toList()..sort();
      final lastWord = words.reduce((latest, word) {
        final wordEnd = word.start! + word.duration!;
        final latestEnd = latest.start! + latest.duration!;
        return wordEnd > latestEnd ? word : latest;
      });
      ranges.add((
        pageIndex: pageIndex,
        start: starts.first,
        end: lastWord.start! + lastWord.duration!,
        lastWord: lastWord,
      ));
    }
    return ranges;
  }

  Duration _pageTurnBoundary(
    ({int pageIndex, Duration start, Duration end, ReadAlongWord lastWord})
    currentPage,
    ({int pageIndex, Duration start, Duration end, ReadAlongWord lastWord})
    nextPage,
  ) {
    final gap = nextPage.start - currentPage.end;
    if (gap <= Duration.zero) return currentPage.end;
    return currentPage.end + Duration(milliseconds: gap.inMilliseconds ~/ 2);
  }

  ({int pageIndex, Duration position})? _pageBoundaryCrossed(
    Duration previousPosition,
    Duration position,
  ) {
    final ranges = _alignedPageRanges();
    for (var index = 0; index < ranges.length - 1; index++) {
      final boundary = _pageTurnBoundary(ranges[index], ranges[index + 1]);
      if (previousPosition < boundary && position >= boundary) {
        return (pageIndex: ranges[index].pageIndex, position: boundary);
      }
    }
    return null;
  }

  int pageIndexForPosition(Duration position) {
    final pages = _document?.pages;
    if (pages == null || pages.isEmpty) return 0;
    final ranges = _alignedPageRanges();
    if (ranges.isEmpty) return 0;
    for (var index = 0; index < ranges.length - 1; index++) {
      if (position < _pageTurnBoundary(ranges[index], ranges[index + 1])) {
        return ranges[index].pageIndex;
      }
    }
    return ranges.last.pageIndex;
  }

  Duration? pageStartPosition(int pageIndex) {
    final pages = _document?.pages;
    if (pages == null || pageIndex < 0 || pageIndex >= pages.length) {
      return null;
    }
    for (final range in _alignedPageRanges()) {
      if (range.pageIndex == pageIndex) return range.start;
    }
    return null;
  }

  ReadAlongWord? _nearestWordForPosition(Duration position) {
    ReadAlongWord? candidate;
    for (final word in _document?.words ?? const <ReadAlongWord>[]) {
      if (!word.isAligned) continue;
      final start = word.start!;
      final end = start + word.duration!;
      if (position >= start && position < end) return word;
      if (start <= position) {
        candidate = word;
      } else if (candidate == null) {
        return word;
      }
    }
    return candidate;
  }

  ReadAlongWord? _nextAlignedPage(int pageIndex) {
    final pages = _document?.pages;
    if (pages == null) return null;
    for (final page in pages.skip(pageIndex + 1)) {
      ReadAlongWord? firstWord;
      for (final word
          in page.paragraphs
              .expand((paragraph) => paragraph.sentences)
              .expand((sentence) => sentence.segments)
              .whereType<ReadAlongWord>()
              .where((word) => word.isAligned)) {
        if (firstWord == null || word.start! < firstWord.start!) {
          firstWord = word;
        }
      }
      if (firstWord != null) return firstWord;
    }
    return null;
  }

  void togglePagePlaybackMode() {
    _pauseAtPageEnds = !_pauseAtPageEnds;
    _lastPosition = audioManager.position;
    notifyListeners();
  }

  void preparePlaybackFromPage(int pageIndex) {
    final position = pageStartPosition(pageIndex);
    if (position != null) audioManager.preparePlaybackFromPosition(position);
  }

  Future<void> playWordById(String id) async {
    final word = _document?.words.where((item) => item.id == id).firstOrNull;
    if (word == null || !word.isAligned || !audioManager.canPlay) return;
    _manuallyHighlightedWordId = word.id;
    _activeWordId = word.id;
    notifyListeners();
    await audioManager.playWord(word.start!, word.duration!);
  }

  void clearManualHighlight() {
    if (_manuallyHighlightedWordId == null) return;
    _manuallyHighlightedWordId = null;
    _updateActiveWord(audioManager.displayPosition);
    notifyListeners();
  }

  String getImageAsset(String imageUrl) {
    final folder = imagesFolder?.trim();
    final imagePath = imageUrl.replaceFirst(RegExp(r'^(?:\./|/)+'), '');
    if (folder == null || folder.isEmpty) return imagePath;
    return '${folder.replaceFirst(RegExp(r'/+$'), '')}/$imagePath';
  }

  @override
  void dispose() {
    _disposed = true;
    audioManager.removeListener(_handleAudioChanged);
    super.dispose();
  }
}
