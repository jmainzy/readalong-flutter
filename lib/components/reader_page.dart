import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  final Map<String, GlobalKey> _sentenceKeys = {};
  final Map<String, GlobalKey> _wordSentenceKeys = {};
  final GlobalKey _textViewportKey = GlobalKey();
  final GlobalKey _imageHeaderBoxKey = GlobalKey();
  final ScrollController _textScrollController = ScrollController();
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;
  double _imageAspectRatio = 1;
  String? _lastActiveWordId;

  @override
  void initState() {
    super.initState();
    _lastActiveWordId = widget.manager.activeWordId;
    widget.manager.addListener(_handleManagerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToActiveSentence();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImageDimensions();
  }

  @override
  void didUpdateWidget(covariant ReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manager != widget.manager) {
      oldWidget.manager.removeListener(_handleManagerChanged);
      widget.manager.addListener(_handleManagerChanged);
      _lastActiveWordId = widget.manager.activeWordId;
    }
    if (oldWidget.page.id != widget.page.id ||
        oldWidget.manager != widget.manager ||
        oldWidget.audioEnabled != widget.audioEnabled) {
      _disposeWordRecognizers();
    }
    if (oldWidget.page.id != widget.page.id) {
      _sentenceKeys.clear();
      if (_textScrollController.hasClients) _textScrollController.jumpTo(0);
    }
    if (oldWidget.imageUri != widget.imageUri) {
      _resolveImageDimensions();
    }
  }

  @override
  void dispose() {
    widget.manager.removeListener(_handleManagerChanged);
    _removeImageStreamListener();
    _disposeWordRecognizers();
    _textScrollController.dispose();
    super.dispose();
  }

  void _resolveImageDimensions() {
    _removeImageStreamListener();
    if (widget.imageUri == null) {
      _imageAspectRatio = 1;
      return;
    }

    final stream = AssetImage(widget.imageUri!)
        .resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (imageInfo, _) {
        final aspectRatio = imageInfo.image.width / imageInfo.image.height;
        if (!mounted || aspectRatio == _imageAspectRatio) return;
        setState(() => _imageAspectRatio = aspectRatio);
      },
      onError: (error, stackTrace) {
        // The Image widget's errorBuilder displays the loading failure.
      },
    );
    _imageStream = stream;
    _imageStreamListener = listener;
    stream.addListener(listener);
  }

  void _removeImageStreamListener() {
    final stream = _imageStream;
    final listener = _imageStreamListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _imageStream = null;
    _imageStreamListener = null;
  }

  void _handleManagerChanged() {
    final activeWordId = widget.manager.activeWordId;
    if (activeWordId == _lastActiveWordId) return;
    _lastActiveWordId = activeWordId;
    if (!mounted) return;
    setState(() {});
    if (activeWordId != null &&
        (widget.manager.isPlaying || widget.manager.isSeeking)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToActiveSentence();
      });
    }
  }

  void _scrollToActiveSentence() {
    final activeWordId = widget.manager.activeWordId;
    if (activeWordId == null ||
        (!widget.manager.isPlaying && !widget.manager.isSeeking) ||
        !_textScrollController.hasClients) {
      return;
    }

    final sentenceKey = _wordSentenceKeys[activeWordId];
    final sentenceRenderObject = sentenceKey?.currentContext
        ?.findRenderObject();
    final viewportRenderObject = _textViewportKey.currentContext
        ?.findRenderObject();
    if (sentenceKey == null ||
        sentenceRenderObject is! RenderParagraph ||
        viewportRenderObject is! RenderBox) {
      return;
    }

    final sentenceTop = sentenceRenderObject.localToGlobal(Offset.zero).dy;
    final viewportTop = viewportRenderObject.localToGlobal(Offset.zero).dy;
    final imageHeaderRenderObject = _imageHeaderBoxKey.currentContext
        ?.findRenderObject();
    final buffer = 62.0; // Add some padding to the top of the viewport
    final textTop =
        viewportTop +
        (imageHeaderRenderObject is RenderBox ? 200.0 : 0.0) +
        buffer;
    final scrollDelta = sentenceTop - textTop;
    if (scrollDelta == 0) return;

    final target = (_textScrollController.offset + scrollDelta)
        .clamp(
          _textScrollController.position.minScrollExtent,
          _textScrollController.position.maxScrollExtent,
        )
        .toDouble();
    if (target == _textScrollController.offset) return;
    unawaited(
      _textScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      ),
    );
  }

  void _disposeWordRecognizers() {
    for (final recognizer in _wordRecognizers.values) {
      recognizer.dispose();
    }
    _wordRecognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _wordSentenceKeys.clear();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final imageHeight = width.isFinite
                  ? width / _imageAspectRatio
                  : 200.0;
              return CustomScrollView(
                key: _textViewportKey,
                controller: _textScrollController,
                slivers: [
                  if (widget.imageUri != null)
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _CollapsingImageHeaderDelegate(
                        imageUri: widget.imageUri!,
                        imageBoxKey: _imageHeaderBoxKey,
                        maxHeight: imageHeight < 200 ? 200 : imageHeight,
                        errorMessage:
                            'Unable to load page image: ${page.imageUrl}',
                        errorColor: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                          for (final (paragraphIndex, paragraph)
                              in page.paragraphs.indexed)
                            _buildParagraph(context, paragraph, paragraphIndex),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildParagraph(
    BuildContext context,
    ReadAlongParagraph paragraph,
    int paragraphIndex,
  ) {
    final sentences = paragraph.sentences
        .where((sentence) => widget.showTranslations || !sentence.isTranslation)
        .toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (sentenceIndex, sentence) in sentences.indexed)
            Text.rich(
              key: _sentenceKeys.putIfAbsent(
                '$paragraphIndex:$sentenceIndex',
                GlobalKey.new,
              ),
              TextSpan(
                children: [
                  for (final segment in sentence.segments)
                    _buildPositionedTextSpan(
                      context,
                      segment,
                      paragraphIndex,
                      sentenceIndex,
                    ),
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

  TextSpan _buildPositionedTextSpan(
    BuildContext context,
    ReadAlongSegment segment,
    int paragraphIndex,
    int sentenceIndex,
  ) {
    final sentenceKey = _sentenceKeys['$paragraphIndex:$sentenceIndex']!;
    if (segment is ReadAlongWord) {
      _wordSentenceKeys[segment.id] = sentenceKey;
    }
    return _buildTextSpan(context, segment);
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

class _CollapsingImageHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _CollapsingImageHeaderDelegate({
    required this.imageUri,
    required this.imageBoxKey,
    required this.maxHeight,
    required this.errorMessage,
    required this.errorColor,
  });

  final String imageUri;
  final GlobalKey imageBoxKey;
  final double maxHeight;
  final String errorMessage;
  final Color errorColor;

  @override
  double get minExtent => 200;

  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(
      key: imageBoxKey,
      child: Image.asset(
        imageUri,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              errorMessage,
              style: TextStyle(color: errorColor),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _CollapsingImageHeaderDelegate oldDelegate) {
    return imageUri != oldDelegate.imageUri ||
        imageBoxKey != oldDelegate.imageBoxKey ||
        maxHeight != oldDelegate.maxHeight ||
        errorMessage != oldDelegate.errorMessage ||
        errorColor != oldDelegate.errorColor;
  }
}
