import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'components/audio_widget.dart';
import 'manager.dart';
import 'models.dart';

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
    this.audioSource,
    this.showTranslations = true,
    this.textStyle,
    this.highlightColor,
  }) : assert((xml == null) != (xmlAsset == null));

  /// XML contents of a `.readalong` document.
  final String? xml;

  /// Flutter asset path for a `.readalong` document.
  final String? xmlAsset;

  /// Audio to play alongside the aligned text.
  ///
  /// Use `AudioSource.asset(...)`, `AudioSource.uri(...)`, or another
  /// `AudioSource` supported by `just_audio`.
  final AudioSource? audioSource;

  /// Whether translation sentences in the XML should be displayed.
  final bool showTranslations;

  /// Optional base style for the document text.
  final TextStyle? textStyle;

  /// Optional background color for the word currently being spoken.
  final Color? highlightColor;

  @override
  State<ReadAlong> createState() => _ReadAlongState();
}

class _ReadAlongState extends State<ReadAlong> {
  late final Manager _manager;
  final Map<String, TapGestureRecognizer> _wordRecognizers = {};

  @override
  void initState() {
    super.initState();
    _manager = Manager(
      xml: widget.xml,
      xmlAsset: widget.xmlAsset,
      audioSource: widget.audioSource,
    );
    unawaited(_manager.initialize());
  }

  @override
  void didUpdateWidget(covariant ReadAlong oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.xml != widget.xml ||
        oldWidget.xmlAsset != widget.xmlAsset ||
        oldWidget.audioSource != widget.audioSource) {
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
    for (final recognizer in _wordRecognizers.values) {
      recognizer.dispose();
    }
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

        return Column(
          children: [
            Expanded(
              child: ListView(
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
                  for (final (pageIndex, page) in document.pages.indexed)
                    _buildPage(context, page, pageIndex, document.pages.length),
                ],
              ),
            ),
            widget.audioSource != null
                ? Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AudioPlayerWidget(manager: _manager),
                      ),
                    ],
                  )
                : Container(),
          ],
        );
      },
    );
  }



  Widget _buildPage(
    BuildContext context,
    ReadAlongPage page,
    int pageIndex,
    int pageCount,
  ) {
    return Padding(
      padding: EdgeInsets.only(bottom: pageIndex == pageCount - 1 ? 0 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pageCount > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Page ${pageIndex + 1} of $pageCount',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          for (final paragraph in page.paragraphs)
            _buildParagraph(context, paragraph),
        ],
      ),
    );
  }

  Widget _buildParagraph(BuildContext context, ReadAlongParagraph paragraph) {
    final sentences = paragraph.sentences
        .where((sentence) => widget.showTranslations || !sentence.isTranslation)
        .toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final sentence in sentences)
            Text.rich(
              TextSpan(
                children: [
                  for (final segment in sentence.segments)
                    _buildTextSpan(context, segment),
                ],
              ),
              style: widget.textStyle ?? Theme.of(context).textTheme.bodyLarge,
            ),
        ],
      ),
    );
  }

  TextSpan _buildTextSpan(BuildContext context, ReadAlongSegment segment) {
    if (segment is! ReadAlongWord) {
      return TextSpan(text: segment.text);
    }

    final isActive = segment.id == _manager.activeWordId;
    final aligned = segment.isAligned;
    final recognizer = aligned && widget.audioSource != null
        ? _wordRecognizers.putIfAbsent(
            segment.id,
            () =>
                TapGestureRecognizer()
                  ..onTap = () => unawaited(_manager.playWordById(segment.id)),
          )
        : null;

    return TextSpan(
      text: segment.text,
      recognizer: recognizer,
      style: TextStyle(
        backgroundColor: isActive
            ? widget.highlightColor ??
                  Theme.of(context).colorScheme.primaryContainer
            : null,
        decoration: aligned && widget.audioSource != null
            ? TextDecoration.underline
            : null,
        decorationStyle: TextDecorationStyle.dotted,
      ),
    );
  }
}
