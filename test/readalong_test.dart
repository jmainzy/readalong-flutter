import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
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

const _translationXml = '''
<read-along>
  <text xml:lang="eng">
    <body>
      <div type="page" id="page-1">
        <p>
          <s id="sentence-1"><w id="word-1" time="0.25" dur="0.5">Hello</w></s>
          <s id="sentence-2" class="translation">Hola</s>
        </p>
      </div>
    </body>
  </text>
</read-along>
''';

const _imageXml = '''
<read-along>
  <text xml:lang="eng">
    <body>
      <div type="page" id="page-1">
        <p><s id="sentence-1">Story text</s></p>
        <graphic url="example01.jpg" />
      </div>
    </body>
  </text>
</read-along>
''';

const _twoPageXml = '''
<read-along>
  <text xml:lang="eng">
    <body>
      <div type="page" id="page-1">
        <p><s id="sentence-1">First page words</s></p>
        <graphic url="first.jpg" />
      </div>
      <div type="page" id="page-2">
        <p><s id="sentence-2">Second page words</s></p>
        <graphic url="second.jpg" />
      </div>
    </body>
  </text>
</read-along>
''';

final _longPageXml =
    '''
<read-along>
  <text xml:lang="eng">
    <body>
      <div type="page" id="long-page">
        <graphic url="example01.jpg" />
        ${List.generate(12, (index) => '<p><s id="sentence-$index">Paragraph $index with enough text to fill the page and continue scrolling.</s></p>').join()}
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

  testWidgets('speed menu shows a marked horizontal speed slider', (
    tester,
  ) async {
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
    final speedSlider = tester.widget<Slider>(find.byType(Slider).last);
    expect(speedSlider.divisions, 6);
    final sliderRect = tester.getRect(find.byType(Slider).last);
    await tester.tapAt(
      Offset(
        sliderRect.left + 24 + (sliderRect.width - 48) * 5 / 6,
        sliderRect.center.dy,
      ),
    );
    await tester.pumpAndSettle();
    expect(manager.speed, 1.5);
  });

  testWidgets('audio controls show title, full-width timeline, and actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final manager = Manager(xml: _sampleXml, xmlAsset: null, audioSource: null);
    await manager.initialize();
    addTearDown(manager.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: AudioPlayerWidget(manager: manager, title: 'Speaker name'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Speaker name'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('--:--'), findsOneWidget);

    final sliderRect = tester.getRect(find.byType(Slider));
    expect(sliderRect.width, greaterThanOrEqualTo(320));

    final playButtonRect = tester.getRect(find.byTooltip('Play'));
    final speedButtonRect = tester.getRect(find.byTooltip('Adjust speed'));
    expect(playButtonRect.center.dx, closeTo(sliderRect.center.dx, 1));
    expect(speedButtonRect.right, closeTo(sliderRect.right, 1));
    expect(playButtonRect.top, greaterThan(sliderRect.bottom));
  });

  testWidgets('loads page image from the provided images folder', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          height: 500,
          child: ReadAlong(xml: _imageXml, imagesFolder: 'assets/images/'),
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/images/example01.jpg',
    );
    expect(find.text('Story text'), findsOneWidget);
  });

  testWidgets(
    'shows one image-first page with fixed page navigation controls',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final audioSource = AudioSource.asset('missing-audio.mp3');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 800,
              child: ReadAlong(
                xml: _twoPageXml,
                imagesFolder: 'assets/images',
                audioSource: audioSource,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      IconButton pageButton(String tooltip) => tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(IconButton),
        ),
      );

      expect(find.text('First page words'), findsOneWidget);
      expect(find.text('Second page words'), findsNothing);
      expect(find.byType(Image), findsOneWidget);
      final firstImageTop = tester.getTopLeft(find.byType(Image)).dy;
      final firstTextTop = tester.getTopLeft(find.text('First page words')).dy;
      expect(firstImageTop, lessThan(firstTextTop));
      expect(pageButton('Previous page').onPressed, isNull);
      expect(pageButton('Next page').onPressed, isNotNull);
      expect(
        tester
            .widget<Visibility>(
              find.ancestor(
                of: find.byTooltip('Previous page'),
                matching: find.byType(Visibility),
              ),
            )
            .visible,
        isFalse,
      );
      expect(find.byType(PageView), findsOneWidget);

      final nextButtonTop = tester.getTopLeft(find.byTooltip('Next page')).dy;
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();

      expect(find.text('First page words'), findsNothing);
      expect(find.text('Second page words'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(tester.getTopLeft(find.byTooltip('Next page')).dy, nextButtonTop);
      expect(pageButton('Previous page').onPressed, isNotNull);
      expect(pageButton('Next page').onPressed, isNull);
      expect(
        tester
            .widget<Visibility>(
              find.ancestor(
                of: find.byTooltip('Next page'),
                matching: find.byType(Visibility),
              ),
            )
            .visible,
        isFalse,
      );

      await tester.tap(find.byTooltip('Previous page'));
      await tester.pumpAndSettle();
      expect(find.text('First page words'), findsOneWidget);

      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('Second page words'), findsOneWidget);
    },
  );

  testWidgets('page text scrolls while the page image stays fixed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 800,
          child: ReadAlong(xml: _longPageXml, imagesFolder: 'assets/images'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final textScrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    final imageTop = tester.getTopLeft(find.byType(Image)).dy;

    await tester.drag(find.byType(ListView), const Offset(0, -180));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.byType(Image)).dy, imageTop);
    expect(textScrollable.position.pixels, greaterThan(0));
  });

  testWidgets('replay invokes the first-page callback and restarts audio', (
    tester,
  ) async {
    final manager = _ReplayManager();
    addTearDown(manager.dispose);
    var replayCallbackCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: AudioPlayerWidget(
                manager: manager,
                onReplay: () => replayCallbackCalled = true,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Replay'));
    await tester.pump();

    expect(replayCallbackCalled, isTrue);
    expect(manager.replayCalled, isTrue);
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

  testWidgets(
    'uses distinct default and customizable translation text styles',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SizedBox(height: 500, child: ReadAlong(xml: _translationXml)),
        ),
      );
      await tester.pumpAndSettle();

      RichText findRichTextContaining(String text) => tester.widget<RichText>(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText && widget.text.toPlainText().contains(text),
        ),
      );
      final mainText = findRichTextContaining('Hello');
      final translation = findRichTextContaining('Hola');

      expect(mainText.text.style?.fontSize, 20);
      expect(translation.text.style?.fontSize, 14);
      expect(translation.text.style?.color, Colors.grey.shade600);

      await tester.pumpWidget(
        const MaterialApp(
          home: SizedBox(
            height: 500,
            child: ReadAlong(
              xml: _translationXml,
              textStyle: TextStyle(fontSize: 24),
              translationTextStyle: TextStyle(fontSize: 12, color: Colors.blue),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(findRichTextContaining('Hello').text.style?.fontSize, 24);
      expect(findRichTextContaining('Hola').text.style?.fontSize, 12);
      expect(findRichTextContaining('Hola').text.style?.color, Colors.blue);
    },
  );
}

class _ReplayManager extends Manager {
  _ReplayManager() : super(xml: _sampleXml, xmlAsset: null, audioSource: null);

  final ValueNotifier<ButtonState> _completedState = ValueNotifier(
    ButtonState.completed,
  );
  bool replayCalled = false;

  @override
  ValueListenable<ButtonState> get buttonState => _completedState;

  @override
  Future<void> replay() async {
    replayCalled = true;
  }

  @override
  void dispose() {
    _completedState.dispose();
    super.dispose();
  }
}
