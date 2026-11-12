import 'package:readalong/models/readalong_document.dart';
import 'package:xml/xml.dart';

class ReadalongParser {
  /// Parses a `.readalong` or ELAN `.eaf` XML document.
  ///
  /// ReadAlong pages are read from `div[type="page"]`; word timings are read
  /// from `w` elements with `id`, `time`, and `dur` attributes. ELAN
  /// transcription annotations are represented as sentence-sized aligned
  /// segments, with linked translation annotations rendered beneath them.
  ReadAlongDocument parseXml(String source) {
    final document = XmlDocument.parse(source);
    if (document.rootElement.name.local == 'ANNOTATION_DOCUMENT') {
      return _parseElanDocument(document);
    }

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

  ReadAlongDocument _parseElanDocument(XmlDocument document) {
    final root = document.rootElement;
    final timeOrder = root.descendants.whereType<XmlElement>().where(
      (element) => element.name.local == 'TIME_SLOT',
    );
    final timeSlots = <String, Duration>{};
    final timeUnits = root
        .getElement('HEADER')
        ?.getAttribute('TIME_UNITS');
    final millisecondsPerUnit = switch (timeUnits) {
      'seconds' => 1000.0,
      'milliseconds' || null => 1.0,
      _ => throw FormatException('Unsupported ELAN time units: $timeUnits'),
    };

    for (final slot in timeOrder) {
      final id = slot.getAttribute('TIME_SLOT_ID');
      final value = slot.getAttribute('TIME_VALUE');
      if (id == null || value == null) continue;

      final time = double.tryParse(value);
      if (time == null || !time.isFinite || time < 0) {
        throw FormatException('Invalid ELAN TIME_VALUE "$value" on "$id".');
      }
      timeSlots[id] = Duration(
        milliseconds: (time * millisecondsPerUnit).round(),
      );
    }

    final tiers = root.childElements
        .where((element) => element.name.local == 'TIER')
        .toList();
    final transcriptionTier = tiers.where((tier) {
      return tier.getAttribute('TIER_ID') == 'Transcription' ||
          tier.getAttribute('LINGUISTIC_TYPE_REF') == 'Transcription';
    }).firstOrNull;
    if (transcriptionTier == null) {
      throw const FormatException(
        'The ELAN document does not contain a Transcription tier.',
      );
    }

    final transcriptionTierId =
        transcriptionTier.getAttribute('TIER_ID') ?? 'Transcription';
    final translations = <String, List<ReadAlongSentence>>{};
    for (final tier in tiers.where((tier) {
      return tier.getAttribute('PARENT_REF') == transcriptionTierId ||
          tier.getAttribute('LINGUISTIC_TYPE_REF') == 'Translation';
    })) {
      for (final annotation in tier.childElements.where(
        (element) => element.name.local == 'ANNOTATION',
      )) {
        final reference = annotation.descendants
            .whereType<XmlElement>()
            .where((element) => element.name.local == 'REF_ANNOTATION')
            .firstOrNull;
        if (reference == null) continue;

        final targetId = reference.getAttribute('ANNOTATION_REF');
        final annotationId = reference.getAttribute('ANNOTATION_ID');
        final text = _annotationText(reference);
        if (targetId == null || text.isEmpty) continue;
        translations
            .putIfAbsent(targetId, () => [])
            .add(
              ReadAlongSentence(
                id: annotationId,
                isTranslation: true,
                segments: [ReadAlongText(text: text)],
              ),
            );
      }
    }

    Duration timeForSlot(String? slotId, String annotationId) {
      final time = slotId == null ? null : timeSlots[slotId];
      if (time == null) {
        throw FormatException(
          'ELAN annotation "$annotationId" references a missing or '
          'unaligned time slot "$slotId".',
        );
      }
      return time;
    }

    final paragraphs = <ReadAlongParagraph>[];
    for (final annotation in transcriptionTier.childElements.where(
      (element) => element.name.local == 'ANNOTATION',
    )) {
      final aligned = annotation.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'ALIGNABLE_ANNOTATION')
          .firstOrNull;
      if (aligned == null) continue;

      final id = aligned.getAttribute('ANNOTATION_ID');
      final text = _annotationText(aligned);
      if (text.isEmpty) continue;
      final annotationId = id ?? 'elan-${paragraphs.length}';
      final start = timeForSlot(
        aligned.getAttribute('TIME_SLOT_REF1'),
        annotationId,
      );
      final end = timeForSlot(
        aligned.getAttribute('TIME_SLOT_REF2'),
        annotationId,
      );
      if (end < start) {
        throw FormatException(
          'ELAN annotation "$annotationId" ends before it starts.',
        );
      }

      final sentence = ReadAlongSentence(
        id: id,
        segments: [
          ReadAlongWord(
            text: text,
            id: annotationId,
            start: start,
            duration: end - start,
          ),
        ],
      );
      paragraphs.add(
        ReadAlongParagraph(
          sentences: [sentence, ...?translations[id]],
        ),
      );
    }

    if (paragraphs.isEmpty) {
      throw const FormatException(
        'The ELAN Transcription tier does not contain any timed text.',
      );
    }

    final metadata = <String, String>{};
    final author = root.getAttribute('AUTHOR');
    final date = root.getAttribute('DATE');
    if (author != null && author.isNotEmpty) metadata['author'] = author;
    if (date != null && date.isNotEmpty) metadata['date'] = date;

    return ReadAlongDocument(
      pages: [ReadAlongPage(id: 'elan-page', paragraphs: paragraphs)],
      metadata: metadata,
    );
  }

  String _annotationText(XmlElement annotation) {
    return annotation.descendants
            .whereType<XmlElement>()
            .where((element) => element.name.local == 'ANNOTATION_VALUE')
            .firstOrNull
            ?.innerText
            .trim() ??
        '';
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
