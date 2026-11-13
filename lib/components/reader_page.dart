import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:readalong/managers/text_manager.dart';
import 'package:readalong/models/readalong_document.dart';

class ReaderPage extends StatefulWidget {
  final ReadAlongPage page;
  final TextStyle? translationTextStyle;
  final TextStyle? textStyle;
  final bool showTranslations;
  final Color? highlightColor;
  final String? imageUri;
  final VoidCallback? onBackgroundTap;
  final ValueChanged<double>? onTextScrollOffsetChanged;
  final TextManager manager;
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
    this.onBackgroundTap,
    this.onTextScrollOffsetChanged,
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
  GlobalKey? _lastAutoScrolledSentenceKey;
  GlobalKey? _pendingAutoScrolledSentenceKey;
  bool _hasRestoredScroll = false;

  @override
  void initState() {
    super.initState();
    _lastActiveWordId = widget.manager.activeWordId;
    widget.manager.addListener(_handleManagerChanged);
    _textScrollController.addListener(_reportTextScrollOffset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportTextScrollOffset();
      if (widget.manager.audioManager.position > Duration.zero) {
        _hasRestoredScroll = true;
        _scrollToActiveSentence(force: true);
      }
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
      _lastAutoScrolledSentenceKey = null;
      _pendingAutoScrolledSentenceKey = null;
      _hasRestoredScroll = false;
      if (_textScrollController.hasClients) _textScrollController.jumpTo(0);
    }
    if (oldWidget.imageUri != widget.imageUri) {
      _resolveImageDimensions();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToActiveSentence();
    });
  }

  @override
  void dispose() {
    widget.manager.removeListener(_handleManagerChanged);
    _removeImageStreamListener();
    _disposeWordRecognizers();
    _textScrollController.removeListener(_reportTextScrollOffset);
    _textScrollController.dispose();
    super.dispose();
  }

  void _reportTextScrollOffset() {
    if (!_textScrollController.hasClients) return;
    widget.onTextScrollOffsetChanged?.call(_textScrollController.offset);
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
    if (activeWordId != _lastActiveWordId) {
      _lastActiveWordId = activeWordId;
      if (mounted) setState(() {});
    }

    if (!_hasRestoredScroll &&
        widget.manager.audioManager.position > Duration.zero) {
      _hasRestoredScroll = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToActiveSentence(force: true);
      });
      return;
    }

    final activeSentenceKey = activeWordId == null
        ? null
        : _wordSentenceKeys[activeWordId];
    if (activeWordId != null &&
        activeSentenceKey != _lastAutoScrolledSentenceKey &&
        activeSentenceKey != _pendingAutoScrolledSentenceKey &&
        (widget.manager.audioManager.isPlaying ||
            widget.manager.audioManager.isSeeking)) {
      _pendingAutoScrolledSentenceKey = activeSentenceKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pendingAutoScrolledSentenceKey == activeSentenceKey) {
          _pendingAutoScrolledSentenceKey = null;
        }
        if (!mounted ||
            _wordSentenceKeys[widget.manager.activeWordId] !=
                activeSentenceKey) {
          return;
        }
        _scrollToActiveSentence();
      });
    }
  }

  ReadAlongWord? _nearestWordForPosition(Duration position) {
    ReadAlongWord? candidate;
    for (final paragraph in page.paragraphs) {
      for (final sentence in paragraph.sentences) {
        for (final segment in sentence.segments) {
          if (segment is ReadAlongWord && segment.isAligned) {
            final start = segment.start!;
            final end = start + segment.duration!;
            if (position >= start && position <= end) {
              return segment;
            }
            if (start <= position) {
              candidate = segment;
            } else if (candidate == null) {
              return segment;
            }
          }
        }
      }
    }
    return candidate;
  }

  void _scrollToActiveSentence({bool force = false}) {
    if ((!force &&
            !widget.manager.audioManager.isPlaying &&
            !widget.manager.audioManager.isSeeking) ||
        !_textScrollController.hasClients) {
      return;
    }

    final activeWordId =
        widget.manager.activeWordId ??
        _nearestWordForPosition(widget.manager.audioManager.displayPosition)
            ?.id;
    if (activeWordId == null) return;

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
    if (!force && sentenceKey == _lastAutoScrolledSentenceKey) return;
    _lastAutoScrolledSentenceKey = sentenceKey;

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
    if (force) {
      _textScrollController.jumpTo(target);
    } else {
      unawaited(
        _textScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        ),
      );
    }
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
              final viewportHeight = MediaQuery.sizeOf(context).height;
              final isCompactLandscape =
                  widget.imageUri != null &&
                  MediaQuery.orientationOf(context) == Orientation.landscape &&
                  viewportHeight < 600;
              final availableHeight = constraints.maxHeight < viewportHeight
                  ? constraints.maxHeight
                  : viewportHeight;
              final maxImageHeight = availableHeight * 0.5;
              final minImageHeight = maxImageHeight.clamp(0.0, 200.0);
              final imageHeight = width.isFinite
                  ? width / _imageAspectRatio
                  : 200.0;
              final headerHeight = imageHeight.clamp(
                minImageHeight,
                maxImageHeight,
              );
              final textView = CustomScrollView(
                key: _textViewportKey,
                controller: _textScrollController,
                slivers: [
                  if (widget.imageUri != null && !isCompactLandscape)
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _CollapsingImageHeaderDelegate(
                        imageUri: widget.imageUri!,
                        imageBoxKey: _imageHeaderBoxKey,
                        minHeight: minImageHeight,
                        maxHeight: headerHeight,
                        errorMessage:
                            'Unable to load page image: ${page.imageUrl}',
                        errorColor: Theme.of(context).colorScheme.error,
                        onTap: widget.onBackgroundTap,
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
              final interactiveTextView = GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapUp: _handleTextAreaTap,
                child: textView,
              );
              if (!isCompactLandscape) return interactiveTextView;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: width.isFinite ? width * 0.5 : 320,
                    child: Center(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onBackgroundTap,
                        child: _buildLandscapeImage(
                          context,
                          width.isFinite ? width * 0.5 : 320,
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: interactiveTextView),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  void _handleTextAreaTap(TapUpDetails details) {
    final position = details.globalPosition;
    for (final key in _sentenceKeys.values) {
      final renderObject = key.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) continue;
      final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
      if (rect.contains(position)) return;
    }
    widget.onBackgroundTap?.call();
  }

  Widget _buildLandscapeImage(BuildContext context, double width) {
    return SizedBox(
      width: width,
      child: Image.asset(
        widget.imageUri!,
        fit: BoxFit.fitWidth,
        errorBuilder: (context, error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Unable to load page image: ${page.imageUrl}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
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
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: widget.audioEnabled
                  ? () => _playSentence(sentence)
                  : null,
              child: Text.rich(
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
                              .copyWith(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              )
                    : widget.textStyle ??
                          (Theme.of(context).textTheme.bodyLarge ??
                                  const TextStyle(fontSize: 20))
                              .copyWith(fontSize: 20),
              ),
            ),
        ],
      ),
    );
  }

  void _playSentence(ReadAlongSentence sentence) {
    ReadAlongWord? firstAlignedWord;
    for (final word in sentence.segments.whereType<ReadAlongWord>()) {
      if (!word.isAligned) continue;
      if (firstAlignedWord == null ||
          word.start! < firstAlignedWord.start!) {
        firstAlignedWord = word;
      }
    }
    if (firstAlignedWord != null) {
      unawaited(widget.manager.playWordById(firstAlignedWord.id));
    }
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
    required this.minHeight,
    required this.maxHeight,
    required this.errorMessage,
    required this.errorColor,
    required this.onTap,
  });

  final String imageUri;
  final GlobalKey imageBoxKey;
  final double minHeight;
  final double maxHeight;
  final String errorMessage;
  final Color errorColor;
  final VoidCallback? onTap;

  @override
  double get minExtent => minHeight;

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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
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
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _CollapsingImageHeaderDelegate oldDelegate) {
    return imageUri != oldDelegate.imageUri ||
        imageBoxKey != oldDelegate.imageBoxKey ||
        minHeight != oldDelegate.minHeight ||
        maxHeight != oldDelegate.maxHeight ||
        errorMessage != oldDelegate.errorMessage ||
        errorColor != oldDelegate.errorColor ||
        onTap != oldDelegate.onTap;
  }
}
