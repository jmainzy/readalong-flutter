import 'package:readalong/parser.dart';

/// A parsed ReadAlong document and its optional metadata.
class ReadAlongDocument {
  const ReadAlongDocument({required this.pages, this.metadata = const {}});

  final List<ReadAlongPage> pages;
  final Map<String, String> metadata;

  factory ReadAlongDocument.fromXml(String xmlString) {
    final parser = ReadalongParser();
    return parser.parseXml(xmlString);
  }

  Iterable<ReadAlongWord> get words sync* {
    for (final page in pages) {
      for (final paragraph in page.paragraphs) {
        for (final sentence in paragraph.sentences) {
          for (final segment in sentence.segments) {
            if (segment is ReadAlongWord) yield segment;
          }
        }
      }
    }
  }
}

class ReadAlongPage {
  const ReadAlongPage({
    required this.id,
    required this.paragraphs,
    this.imageUrl,
  });

  final String id;
  final List<ReadAlongParagraph> paragraphs;
  final String? imageUrl;
}

class ReadAlongParagraph {
  const ReadAlongParagraph({required this.sentences});

  final List<ReadAlongSentence> sentences;
}

class ReadAlongSentence {
  const ReadAlongSentence({
    required this.segments,
    this.id,
    this.isTranslation = false,
  });

  final String? id;
  final bool isTranslation;
  final List<ReadAlongSegment> segments;
}

sealed class ReadAlongSegment {
  const ReadAlongSegment({required this.text});

  final String text;
}

class ReadAlongText extends ReadAlongSegment {
  const ReadAlongText({required super.text});
}

class ReadAlongWord extends ReadAlongSegment {
  const ReadAlongWord({
    required super.text,
    required this.id,
    required this.start,
    required this.duration,
  });

  final String id;
  final Duration? start;
  final Duration? duration;

  bool get isAligned => start != null && duration != null;
}
