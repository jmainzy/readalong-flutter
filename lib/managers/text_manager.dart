import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/readalong_document.dart';
import 'audio_manager.dart';
import '../parser.dart';

typedef _AlignedPageRange = ({
  int pageIndex,
  Duration start,
  Duration end,
  ReadAlongWord lastWord,
});

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
  List<ReadAlongWord> _alignedWords = [];
  List<Duration> _alignedWordMaximumEnds = [];
  List<_AlignedPageRange> _pageRanges = [];
  Map<String, ReadAlongWord> _wordsById = {};
  int _lastPageIndex = 0;
  final ValueNotifier<int> _documentRevision = ValueNotifier(0);
  bool _pauseAtPageEnds = false;
  bool _handlingPageBoundary = false;
  bool _disposed = false;
  int _documentConfiguration = 0;

  ReadAlongDocument? get document => _document;
  ValueListenable<int> get documentRevision => _documentRevision;
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
    _alignedWords = [];
    _alignedWordMaximumEnds = [];
    _pageRanges = [];
    _wordsById = {};
    _lastPageIndex = 0;
    _documentRevision.value++;
    notifyListeners();
    try {
      final source = _xml ?? await rootBundle.loadString(_xmlAsset!);
      if (_disposed || configuration != _documentConfiguration) return;
      _document = _parser.parseXml(source);
      _indexDocument(_document!);
      _xmlError = null;
      _lastPosition = audioManager.displayPosition;
      _updateActiveWord(audioManager.displayPosition);
      _lastPageIndex = pageIndexForPosition(audioManager.displayPosition);
    } catch (error) {
      if (_disposed || configuration != _documentConfiguration) return;
      _xmlError = error;
    }
    _documentRevision.value++;
    notifyListeners();
  }

  void _handleAudioChanged() {
    if (_disposed) return;
    final position = audioManager.displayPosition;
    final manuallyHighlightedWord = _manuallyHighlightedWordId == null
        ? null
        : _wordsById[_manuallyHighlightedWordId];
    final previousActiveWordId = _activeWordId;
    final previousPageIndex = _lastPageIndex;
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
    final pageIndex = pageIndexForPosition(position);
    _lastPageIndex = pageIndex;
    if (previousActiveWordId != _activeWordId ||
        previousPageIndex != pageIndex) {
      notifyListeners();
    }
  }

  void _indexDocument(ReadAlongDocument document) {
    _wordsById = {for (final word in document.words) word.id: word};
    _alignedWords = document.words.where((word) => word.isAligned).toList()
      ..sort((first, second) => first.start!.compareTo(second.start!));
    Duration? maximumEnd;
    _alignedWordMaximumEnds = [];
    for (final word in _alignedWords) {
      final wordEnd = word.start! + word.duration!;
      if (maximumEnd == null || wordEnd > maximumEnd) maximumEnd = wordEnd;
      _alignedWordMaximumEnds.add(maximumEnd);
    }
    _pageRanges = _buildAlignedPageRanges(document);
  }

  void _updateActiveWord(Duration position) {
    if (_manuallyHighlightedWordId != null) {
      _activeWordId = _manuallyHighlightedWordId;
      return;
    }
    _activeWordId = _nearestWordForPosition(position)?.id;
  }

  List<_AlignedPageRange> _buildAlignedPageRanges(
    ReadAlongDocument document,
  ) {
    final ranges = <_AlignedPageRange>[];
    final pages = document.pages;
    for (final (pageIndex, page) in pages.indexed) {
      ReadAlongWord? firstWord;
      ReadAlongWord? lastWord;
      for (final paragraph in page.paragraphs) {
        for (final sentence in paragraph.sentences) {
          for (final segment in sentence.segments) {
            if (segment is! ReadAlongWord || !segment.isAligned) continue;
            if (firstWord == null || segment.start! < firstWord.start!) {
              firstWord = segment;
            }
            if (lastWord == null ||
                segment.start! + segment.duration! >
                    lastWord.start! + lastWord.duration!) {
              lastWord = segment;
            }
          }
        }
      }
      if (firstWord == null || lastWord == null) continue;
      ranges.add((
        pageIndex: pageIndex,
        start: firstWord.start!,
        end: lastWord.start! + lastWord.duration!,
        lastWord: lastWord,
      ));
    }
    return ranges;
  }

  Duration _pageTurnBoundary(
    _AlignedPageRange currentPage,
    _AlignedPageRange nextPage,
  ) {
    final gap = nextPage.start - currentPage.end;
    if (gap <= Duration.zero) return currentPage.end;
    return currentPage.end + Duration(milliseconds: gap.inMilliseconds ~/ 2);
  }

  ({int pageIndex, Duration position})? _pageBoundaryCrossed(
    Duration previousPosition,
    Duration position,
  ) {
    final ranges = _pageRanges;
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
    final ranges = _pageRanges;
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
    for (final range in _pageRanges) {
      if (range.pageIndex == pageIndex) return range.start;
    }
    return null;
  }

  ReadAlongWord? _nearestWordForPosition(Duration position) {
    var low = 0;
    var high = _alignedWords.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_alignedWords[middle].start! < position) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low < _alignedWords.length &&
        _alignedWords[low].start == position) {
      return _alignedWords[low];
    }
    var left = 0;
    var right = low;
    while (left < right) {
      final middle = (left + right) ~/ 2;
      if (_alignedWordMaximumEnds[middle] > position) {
        right = middle;
      } else {
        left = middle + 1;
      }
    }
    for (var index = low - 1; index >= left; index--) {
      final word = _alignedWords[index];
      if (position < word.start! + word.duration!) return word;
    }
    if (low < _alignedWords.length) return _alignedWords[low];
    return _alignedWords.isEmpty ? null : _alignedWords.last;
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
    _lastPageIndex = pageIndexForPosition(audioManager.position);
    notifyListeners();
  }

  void preparePlaybackFromPage(int pageIndex) {
    final position = pageStartPosition(pageIndex);
    if (position != null) audioManager.preparePlaybackFromPosition(position);
  }

  Future<void> playWordById(String id) async {
    final word = _wordsById[id];
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
    _documentRevision.dispose();
    super.dispose();
  }
}
