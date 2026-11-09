/// The current location in a ReadAlong document.
class ReadAlongPosition {
  const ReadAlongPosition({
    required this.pageIndex,
    required this.textScrollOffset,
    this.audioPosition,
    this.activeWordId,
  });

  /// Zero-based index of the current page.
  final int pageIndex;

  /// Current audio time, or null when the reader has no audio source.
  final Duration? audioPosition;

  /// ID of the word active at [audioPosition], if any.
  final String? activeWordId;

  /// Vertical scroll offset, in logical pixels, within the current page's text.
  final double textScrollOffset;

  @override
  bool operator ==(Object other) {
    return other is ReadAlongPosition &&
        pageIndex == other.pageIndex &&
        audioPosition == other.audioPosition &&
        activeWordId == other.activeWordId &&
        textScrollOffset == other.textScrollOffset;
  }

  @override
  int get hashCode => Object.hash(
    pageIndex,
    audioPosition,
    activeWordId,
    textScrollOffset,
  );
}
