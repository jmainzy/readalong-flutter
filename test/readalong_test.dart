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

  testWidgets('speed menu is anchored to a bounded button', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final manager = Manager(xml: _sampleXml, xmlAsset: null, audioSource: null);
    await manager.initialize();
    addTearDown(() async {
      manager.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: AudioPlayerWidget(manager: manager),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Adjust speed'));
    await tester.pumpAndSettle();

    final speedButton = find.byTooltip('Adjust speed');
    final buttonRect = tester.getRect(speedButton);
    expect(buttonRect.width, lessThanOrEqualTo(64));
    expect(buttonRect.height, lessThanOrEqualTo(64));
    expect(find.byType(MenuItemButton), findsNWidgets(7));

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
