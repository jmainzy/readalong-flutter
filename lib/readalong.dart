import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:readalong/components/reader_page.dart';
import 'package:readalong/models/readalong_position.dart';
import 'package:readalong/models/playback_controller.dart';

import 'components/audio_widget.dart';
import 'manager.dart';

export 'manager.dart';
export 'models/playback_controller.dart';
export 'models/readalong_position.dart';

/// Displays a ReadAlong XML or ELAN EAF document with aligned audio playback.
///
/// Pass the XML text with [xml], or the path to a Flutter asset with
/// [xmlAsset]. An optional [audioSource] enables playback, word tapping, and
/// active-word highlighting. For example:
///
/// ```dart
/// ReadAlongPlayer(
///   xmlAsset: 'assets/story.eaf',
///   audioSource: AudioSource.asset('assets/story.mp3'),
/// )
/// ```
class ReadAlong extends StatefulWidget {
  const ReadAlong({
    super.key,
    this.xml,
    this.xmlAsset,
    this.imagesFolder,
    this.audioSource,
    this.playbackController,
    this.audioTitle,
    this.onAutoplayChanged,
    this.onSpeedChanged,
    this.onReaderSurfaceTap,
    this.onPositionChanged,
    this.showTranslations = true,
    this.textStyle,
    this.translationTextStyle,
    this.highlightColor,
  }) : assert((xml == null) != (xmlAsset == null)),
       assert(audioSource == null || playbackController == null);

  /// XML contents of a `.readalong` or ELAN `.eaf` document.
  final String? xml;

  /// Flutter asset path for a `.readalong` or ELAN `.eaf` document.
  final String? xmlAsset;

  /// Asset folder containing the page images referenced by the document.
  ///
  /// For example, if a page contains `<graphic url="page1.jpg" />`, provide
  /// `assets/images` to load it from `assets/images/page1.jpg`.
  final String? imagesFolder;

  /// Audio to play alongside the aligned text.
  ///
  /// Use `AudioSource.asset(...)`, `AudioSource.uri(...)`, or another
  /// `AudioSource` supported by `just_audio`.
  final AudioSource? audioSource;

  /// Optional external player synchronized with the reader text.
  ///
  /// Use this instead of [audioSource] when playback is owned by a player
  /// outside this package. The reader's audio widget is hidden so the external
  /// player provides the playback controls. The controller remains owned by
  /// the caller.
  final PlaybackController? playbackController;

  /// Optional title shown above the audio controls, such as a speaker name.
  final String? audioTitle;

  /// Called when the user changes whether playback continues automatically
  /// between pages.
  final ValueChanged<bool>? onAutoplayChanged;

  /// Called when the user changes the playback speed.
  final ValueChanged<double>? onSpeedChanged;

  /// Called when the reader's image or blank text area is tapped.
  final VoidCallback? onReaderSurfaceTap;

  /// Called when the current reading position changes and immediately before
  /// the reader is disposed.
  ///
  /// Use the snapshot to save a bookmark. [ReadAlongPosition.audioPosition]
  /// is null when no audio source is configured.
  final ValueChanged<ReadAlongPosition>? onPositionChanged;

  /// Whether translation sentences in the XML should be displayed.
  final bool showTranslations;

  /// Optional style for the document text.
  ///
  /// By default, the document text uses a larger body style.
  final TextStyle? textStyle;

  /// Optional style for translation text.
  ///
  /// By default, translations use smaller, lighter grey text.
  final TextStyle? translationTextStyle;

  /// Optional background color for the word currently being spoken.
  final Color? highlightColor;

  @override
  State<ReadAlong> createState() => _ReadAlongState();
}

class _ReadAlongState extends State<ReadAlong> {
  late final Manager _manager;
  final PageController _pageController = PageController();
  bool _isFullscreen = false;
  int _currentPageIndex = 0;
  int? _requestedPageIndex;
  final Map<String, double> _textScrollOffsets = {};
  ReadAlongPosition? _lastReportedPosition;

  @override
  void initState() {
    super.initState();
    _manager = Manager(
      xml: widget.xml,
      xmlAsset: widget.xmlAsset,
      audioSource: widget.audioSource,
      playbackController: widget.playbackController,
      imagesFolder: widget.imagesFolder,
    );
    _manager.addListener(_followActiveWord);
    unawaited(_manager.initialize());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isMobilePlatform =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final shouldBeFullscreen =
        isMobilePlatform &&
        MediaQuery.orientationOf(context) == Orientation.landscape;
    if (_isFullscreen == shouldBeFullscreen) return;

    _isFullscreen = shouldBeFullscreen;
    unawaited(_setSystemUiMode(_isFullscreen));
  }

  @override
  void didUpdateWidget(covariant ReadAlong oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onPositionChanged != widget.onPositionChanged) {
      _lastReportedPosition = null;
      _reportPosition();
    }
    if (oldWidget.xml != widget.xml ||
        oldWidget.xmlAsset != widget.xmlAsset ||
        oldWidget.audioSource != widget.audioSource ||
        oldWidget.playbackController != widget.playbackController) {
      _currentPageIndex = 0;
      _requestedPageIndex = null;
      if (_pageController.hasClients) _pageController.jumpToPage(0);
      unawaited(
        _manager.updateSources(
          xml: widget.xml,
          xmlAsset: widget.xmlAsset,
          audioSource: widget.audioSource,
          playbackController: widget.playbackController,
        ),
      );
    }
  }

  @override
  void dispose() {
    _reportPosition(force: true);
    if (_isFullscreen) {
      unawaited(_setSystemUiMode(false));
    }
    _manager.removeListener(_followActiveWord);
    _manager.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _setSystemUiMode(bool fullscreen) {
    if (fullscreen && defaultTargetPlatform == TargetPlatform.iOS) {
      return SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: const [],
      );
    }
    return SystemChrome.setEnabledSystemUIMode(
      fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _manager,
      builder: (context, _) {
        final document = _manager.document;
        if (_manager.xmlError != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Unable to load ReadAlong XML: ${_manager.xmlError}'),
            ),
          );
        }
        if (document == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final targetPage = _manager.pageIndexForPosition(_manager.position);
        if (_currentPageIndex == 0 && targetPage > 0) {
          _currentPageIndex = targetPage;
        }
        if (_currentPageIndex >= document.pages.length) {
          _currentPageIndex = document.pages.length - 1;
        }
        final pageCount = document.pages.length;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              _pageController.hasClients &&
              _pageController.page?.round() != _currentPageIndex) {
            _pageController.jumpToPage(_currentPageIndex);
          }
        });

        return Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: pageCount,
                onPageChanged: (pageIndex) {
                  setState(() {
                    _currentPageIndex = pageIndex;
                  });
                  _reportPosition();
                },
                itemBuilder: (context, pageIndex) {
                  final page = document.pages[pageIndex];
                  return ReaderPage(
                    key: ValueKey(page.id),
                    page: page,
                    manager: _manager,
                    audioEnabled:
                        widget.audioSource != null ||
                        widget.playbackController != null,
                    audioError: _manager.audioError,
                    translationTextStyle: widget.translationTextStyle,
                    textStyle: widget.textStyle,
                    showTranslations: widget.showTranslations,
                    highlightColor: widget.highlightColor,
                    onBackgroundTap: widget.onReaderSurfaceTap,
                    onTextScrollOffsetChanged: (offset) =>
                        _updateTextScrollOffset(page.id, offset),
                    imageUri:
                        widget.imagesFolder != null && page.imageUrl != null
                        ? _manager.getImageAsset(page.imageUrl!)
                        : null,
                  );
                },
              ),
            ),
            widget.audioSource != null
                ? AudioPlayerWidget(
                    manager: _manager,
                    title: widget.audioTitle,
                    onAutoplayChanged: widget.onAutoplayChanged,
                    onSpeedChanged: widget.onSpeedChanged,
                    canGoToPreviousPage: _currentPageIndex > 0,
                    canGoToNextPage: _currentPageIndex < pageCount - 1,
                    onPreviousPage: _goToPreviousPage,
                    onNextPage: _goToNextPage,
                    onReplay: _goToFirstPage,
                  )
                : Container(),
          ],
        );
      },
    );
  }

  void _reportPosition({bool force = false}) {
    final document = _manager.document;
    if (document == null || document.pages.isEmpty) return;
    final pageIndex = _currentPageIndex
        .clamp(0, document.pages.length - 1)
        .toInt();
    final page = document.pages[pageIndex];
    final position = ReadAlongPosition(
      pageIndex: pageIndex,
      audioPosition:
          widget.audioSource == null && widget.playbackController == null
          ? null
          : _manager.position,
      activeWordId:
          widget.audioSource == null && widget.playbackController == null
          ? null
          : _manager.activeWordId,
      textScrollOffset: _textScrollOffsets[page.id] ?? 0,
    );
    if (!force && position == _lastReportedPosition) return;
    _lastReportedPosition = position;
    widget.onPositionChanged?.call(position);
  }

  void _updateTextScrollOffset(String pageId, double offset) {
    if (_textScrollOffsets[pageId] == offset) return;
    _textScrollOffsets[pageId] = offset;
    _reportPosition();
  }

  void _followActiveWord() {
    _reportPosition();
    final pages = _manager.document?.pages;
    if (pages == null || pages.isEmpty) return;

    final targetPageIndex = _manager.pageIndexForPosition(_manager.position);
    if (targetPageIndex != _currentPageIndex) {
      if (_pageController.hasClients) {
        _changePage(targetPageIndex);
      } else {
        _currentPageIndex = targetPageIndex;
      }
    }
  }

  void _goToPreviousPage() {
    if (_currentPageIndex == 0) return;
    _changePage(_currentPageIndex - 1);
  }

  void _goToFirstPage() {
    if (_currentPageIndex == 0) return;
    _changePage(0);
  }

  void _goToNextPage() {
    final pageCount = _manager.document?.pages.length ?? 0;
    if (_currentPageIndex >= pageCount - 1) return;
    _changePage(_currentPageIndex + 1);
  }

  void _changePage(int pageIndex) {
    if (!_pageController.hasClients) {
      _currentPageIndex = pageIndex;
      return;
    }
    if (pageIndex == _currentPageIndex || pageIndex == _requestedPageIndex) {
      return;
    }
    _requestedPageIndex = pageIndex;
    unawaited(_animateToPage(pageIndex));
  }

  Future<void> _animateToPage(int pageIndex) async {
    try {
      await _pageController.animateToPage(
        pageIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } finally {
      if (_requestedPageIndex == pageIndex) _requestedPageIndex = null;
    }
  }
}
