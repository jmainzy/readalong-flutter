import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:readalong/components/reader_page.dart';

import 'components/audio_widget.dart';
import 'manager.dart';

export 'manager.dart';

/// Displays a ReadAlong XML document with word-level audio playback.
///
/// Pass the XML text with [xml], or the path to a Flutter asset with
/// [xmlAsset]. An optional [audioSource] enables playback, word tapping, and
/// active-word highlighting. For example:
///
/// ```dart
/// ReadAlongPlayer(
///   xmlAsset: 'assets/story.readalong',
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
    this.audioTitle,
    this.showTranslations = true,
    this.textStyle,
    this.translationTextStyle,
    this.highlightColor,
  }) : assert((xml == null) != (xmlAsset == null));

  /// XML contents of a `.readalong` document.
  final String? xml;

  /// Flutter asset path for a `.readalong` document.
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

  /// Optional title shown above the audio controls, such as a speaker name.
  final String? audioTitle;

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
  final ScrollController _pageScrollController = ScrollController();
  int _currentPageIndex = 0;

  @override
  void initState() {
    super.initState();
    _manager = Manager(
      xml: widget.xml,
      xmlAsset: widget.xmlAsset,
      audioSource: widget.audioSource,
      imagesFolder: widget.imagesFolder,
    );
    unawaited(_manager.initialize());
  }

  @override
  void didUpdateWidget(covariant ReadAlong oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.xml != widget.xml ||
        oldWidget.xmlAsset != widget.xmlAsset ||
        oldWidget.audioSource != widget.audioSource) {
      _currentPageIndex = 0;
      if (_pageScrollController.hasClients) _pageScrollController.jumpTo(0);
      unawaited(
        _manager.updateSources(
          xml: widget.xml,
          xmlAsset: widget.xmlAsset,
          audioSource: widget.audioSource,
        ),
      );
    }
  }

  @override
  void dispose() {
    _manager.dispose();
    _pageScrollController.dispose();
    super.dispose();
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

        if (_currentPageIndex >= document.pages.length) {
          _currentPageIndex = document.pages.length - 1;
        }
        final pageCount = document.pages.length;
        final page = document.pages[_currentPageIndex];

        return Column(
          children: [
            Expanded(
              child: ListView(
                controller: _pageScrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  if (_manager.audioError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Unable to load or play audio: ${_manager.audioError}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ReaderPage(
                    key: ValueKey(page.id),
                    page: page,
                    manager: _manager,
                    audioEnabled: widget.audioSource != null,
                    translationTextStyle: widget.translationTextStyle,
                    textStyle: widget.textStyle,
                    showTranslations: widget.showTranslations,
                    highlightColor: widget.highlightColor,
                    imageUri: widget.imagesFolder != null && page.imageUrl != null
                        ? _manager.getImageAsset(page.imageUrl!)
                        : null,
                  ),
                ],
              ),
            ),
            widget.audioSource != null
                ? Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AudioPlayerWidget(
                          manager: _manager,
                          title: widget.audioTitle,
                          canGoToPreviousPage: _currentPageIndex > 0,
                          canGoToNextPage: _currentPageIndex < pageCount - 1,
                          onPreviousPage: _goToPreviousPage,
                          onNextPage: _goToNextPage,
                        ),
                      ),
                    ],
                  )
                : Container(),
          ],
        );
      },
    );
  }

  void _goToPreviousPage() {
    if (_currentPageIndex == 0) return;
    setState(() {
      _currentPageIndex--;
    });
    if (_pageScrollController.hasClients) _pageScrollController.jumpTo(0);
  }

  void _goToNextPage() {
    final pageCount = _manager.document?.pages.length ?? 0;
    if (_currentPageIndex >= pageCount - 1) return;
    setState(() {
      _currentPageIndex++;
    });
    if (_pageScrollController.hasClients) _pageScrollController.jumpTo(0);
  }
}
