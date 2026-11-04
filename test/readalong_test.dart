import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readalong/components/audio_widget.dart';
import 'package:readalong/models.dart';
import 'package:readalong/readalong.dart';

const _sampleXml = '''
<read-along>
  <meta name="title" content="Sample story" />
  <text xml:lang="eng">
    <body>
      <div type="page" id="page-1">
        <p>
          <s id="sentence-1"><w id="word-1" time="0.25" dur="0.5">Hello</w>, <w id="word-2" time="0.75" dur="0.4">world</w>!</s>
        </p>
      </div>
    </body>
  </text>
</read-along>
''';

void main() {
  test('Manager loads document and owns playback state', () async {
    final manager = Manager(xml: _sampleXml, xmlAsset: null, audioSource: null);
    addTearDown(manager.dispose);

    await manager.initialize();

    expect(manager.document?.pages.single.id, 'page-1');
    expect(manager.xmlError, isNull);
    expect(manager.isAudioLoading, isFalse);
    expect(manager.position, Duration.zero);
  });

  testWidgets('audio widget opens a compact speed menu above its button', (
    tester,
  ) async {
    final manager = Manager(xml: _sampleXml, xmlAsset: null, audioSource: null);
    await manager.initialize();
    addTearDown(() async {
      manager.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AudioPlayerWidget(manager: manager)),
      ),
    );

    await tester.tap(find.byTooltip('Adjust speed'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(RegExp(r'^(0\.5|0\.75|1|1\.25|1\.5|1\.75|2)x$')),
      findsNWidgets(7),
    );
    final speedButtonTop = tester.getTopLeft(find.byTooltip('Adjust speed')).dy;
    final menuBottom = tester.getBottomRight(find.text('2x')).dy;
    expect(menuBottom, lessThanOrEqualTo(speedButtonTop));

    await tester.tap(find.text('1.25x'));
    await tester.pumpAndSettle();
    expect(manager.speed, 1.25);
    expect(find.text('0.5x'), findsNothing);
  });

  group('ReadAlongDocument.fromXml', () {
    test('parses pages, metadata, and word timing', () {
      final document = ReadAlongDocument.fromXml(_sampleXml);
      final words = document.words.toList();

      expect(document.metadata['title'], 'Sample story');
      expect(document.pages, hasLength(1));
      expect(document.pages.single.id, 'page-1');
      expect(words, hasLength(2));
      expect(words.first.id, 'word-1');
      expect(words.first.text, 'Hello');
      expect(words.first.start, const Duration(milliseconds: 250));
      expect(words.first.duration, const Duration(milliseconds: 500));
      expect(words.last.start, const Duration(milliseconds: 750));
    });

    test('preserves punctuation and whitespace between words', () {
      final sentence = ReadAlongDocument.fromXml(_sampleXml)
          .pages
          .single
          .paragraphs
          .single
          .sentences
          .single;

      expect(
        sentence.segments.map((segment) => segment.text).join(),
        'Hello, world!',
      );
    });

    test('rejects XML without readalong pages', () {
      expect(
        () => ReadAlongDocument.fromXml('<read-along><text /></read-along>'),
        throwsFormatException,
      );
    });
  });

  testWidgets('renders aligned text without requiring an audio source', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(height: 500, child: ReadAlong(xml: _sampleXml)),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(ReadAlong), findsOneWidget);
    expect(find.textContaining('Hello'), findsOneWidget);
    expect(find.textContaining('world'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });
}
