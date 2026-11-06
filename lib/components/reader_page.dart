import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:readalong/manager.dart';
import 'package:readalong/models.dart';

class ReaderPage extends StatefulWidget {
  final ReadAlongPage page;
  final TextStyle? translationTextStyle;
  final TextStyle? textStyle;
  final bool showTranslations;
  final Color? highlightColor;
  final String? imageUri;
  final Manager manager;
  final bool audioEnabled;
  final Object? audioError;

  const ReaderPage({
    super.key,
    required this.page,
    required this.manager,
    this.audioEnabled = false,
    this.audioError,
    this.translationTextStyle,
    this.textStyle,
    this.showTranslations = true,
    this.highlightColor,
    this.imageUri,
  });

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  ReadAlongPage get page => widget.page;
  final Map<String, TapGestureRecognizer> _wordRecognizers = {};

  @override
  void didUpdateWidget(covariant ReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page.id != widget.page.id ||
        oldWidget.manager != widget.manager ||
        oldWidget.audioEnabled != widget.audioEnabled) {
      _disposeWordRecognizers();
    }
  }

  @override
  void dispose() {
    _disposeWordRecognizers();
    super.dispose();
  }

  void _disposeWordRecognizers() {
    for (final recognizer in _wordRecognizers.values) {
      recognizer.dispose();
    }
    _wordRecognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.imageUri != null) ...[
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: Image.asset(
                widget.imageUri!,
                width: double.infinity,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Unable to load page image: ${page.imageUrl}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ],
        Expanded(
          child: ListView(
            padding: EdgeInsets.all(16),
            children: [
              if (widget.audioError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Unable to load or play audio: ${widget.audioError}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              for (final paragraph in page.paragraphs)
                _buildParagraph(context, paragraph),
            ],
          ),
        ),
      ],
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
              style: sentence.isTranslation
                  ? widget.translationTextStyle ??
                        (Theme.of(context).textTheme.bodyMedium ??
                                const TextStyle(fontSize: 14))
                            .copyWith(fontSize: 14, color: Colors.grey.shade600)
                  : widget.textStyle ??
                        (Theme.of(context).textTheme.bodyLarge ??
                                const TextStyle(fontSize: 20))
                            .copyWith(fontSize: 20),
            ),
        ],
      ),
    );
  }

  TextSpan _buildTextSpan(BuildContext context, ReadAlongSegment segment) {
    if (segment is! ReadAlongWord) {
      return TextSpan(text: segment.text);
    }

    final isActive = segment.id == widget.manager.activeWordId;
    final aligned = segment.isAligned;
    final recognizer = aligned && widget.audioEnabled
        ? _wordRecognizers.putIfAbsent(
            segment.id,
            () =>
                TapGestureRecognizer()
                  ..onTap = () =>
                      unawaited(widget.manager.playWordById(segment.id)),
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
      ),
    );
  }
}
