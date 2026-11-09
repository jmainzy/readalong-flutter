import 'package:readalong/models/readalong_document.dart';
import 'package:xml/xml.dart';

class ReadalongParser {
  /// Parses the XML contents of a `.readalong` file.
  ///
  /// Pages are read from `div[type="page"]`; word timings are read from `w`
  /// elements with `id`, `time`, and `dur` attributes. Timings are expressed
  /// in seconds in the XML and exposed as [Duration]s.
  ReadAlongDocument parseXml(String source) {
    final document = XmlDocument.parse(source);
    final pageElements = document.descendants.whereType<XmlElement>().where(
      (element) =>
          element.name.local == 'div' && element.getAttribute('type') == 'page',
    );
    final pages = <ReadAlongPage>[];

    for (final (pageIndex, pageElement) in pageElements.indexed) {
      final paragraphElements = pageElement.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'p');
      final paragraphs = <ReadAlongParagraph>[];

      for (final paragraphElement in paragraphElements) {
        final sentenceElements = paragraphElement.children
            .whereType<XmlElement>()
            .where((element) => element.name.local == 's')
            .toList();

        if (sentenceElements.isEmpty) {
          final segments = _parseSegments(paragraphElement.children);
          if (segments.isNotEmpty) {
            paragraphs.add(
              ReadAlongParagraph(
                sentences: [ReadAlongSentence(segments: segments)],
              ),
            );
          }
          continue;
        }

        paragraphs.add(
          ReadAlongParagraph(
            sentences: sentenceElements.map(_parseSentence).toList(),
          ),
        );
      }

      final graphic = pageElement.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'graphic')
          .firstOrNull;

      pages.add(
        ReadAlongPage(
          id: pageElement.getAttribute('id') ?? 'page-$pageIndex',
          paragraphs: paragraphs,
          imageUrl: graphic?.getAttribute('url'),
        ),
      );
    }

    final metadata = <String, String>{};
    for (final element in document.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'meta') continue;
      final name = element.getAttribute('name');
      final value = element.getAttribute('content');
      if (name != null && value != null) {
        metadata[name] = value.trim();
      }
    }

    if (pages.isEmpty) {
      throw const FormatException(
        'The ReadAlong XML does not contain any div[type="page"] elements.',
      );
    }

    return ReadAlongDocument(pages: pages, metadata: metadata);
  }

  ReadAlongSentence _parseSentence(XmlElement element) {
    return ReadAlongSentence(
      id: element.getAttribute('id'),
      isTranslation: (element.getAttribute('class') ?? '').contains(
        'translation',
      ),
      segments: _parseSegments(element.children),
    );
  }

  List<ReadAlongSegment> _parseSegments(Iterable<XmlNode> nodes) {
    final segments = <ReadAlongSegment>[];

    for (final node in nodes) {
      if (node is XmlText) {
        if (node.value.isNotEmpty) {
          segments.add(ReadAlongText(text: node.value));
        }
      } else if (node is XmlElement && node.name.local.toLowerCase() == 'w') {
        final id = node.getAttribute('id');
        final time = node.getAttribute('time');
        final duration = node.getAttribute('dur');
        final start = _parseSeconds(time, 'time', id);
        final length = _parseSeconds(duration, 'dur', id);

        segments.add(
          ReadAlongWord(
            text: node.innerText,
            id: id ?? '',
            start: id != null && start != null && length != null ? start : null,
            duration: id != null && start != null && length != null
                ? length
                : null,
          ),
        );
      } else if (node is XmlElement) {
        segments.addAll(_parseSegments(node.children));
      }
    }

    return segments;
  }

  Duration? _parseSeconds(String? value, String attribute, String? wordId) {
    if (value == null) return null;
    final seconds = double.tryParse(value);
    if (seconds == null || !seconds.isFinite || seconds < 0) {
      throw FormatException(
        'Invalid "$attribute" value "$value" on ReadAlong word '
        '${wordId == null ? '(without id)' : '"$wordId"'}.',
      );
    }
    return Duration(milliseconds: (seconds * 1000).round());
  }
}
