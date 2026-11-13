import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:readalong/components/audio_widget.dart';
import 'package:readalong/components/reader_page.dart';
import 'package:readalong/models/readalong_document.dart';
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

const _twoAlignedPageXml = '''
<read-along>
  <text xml:lang="eng">
    <body>
      <div type="page" id="page-1">
        <p><s id="sentence-1"><w id="word-1" time="0" dur="1">First page.</w></s></p>
      </div>
      <div type="page" id="page-2">
        <p><s id="sentence-2"><w id="word-2" time="5" dur="1">Second page.</w></s></p>
      </div>
    </body>
  </text>
</read-along>
''';

const _elanXml = '''
<ANNOTATION_DOCUMENT AUTHOR="Test author" DATE="2026-01-01">
  <HEADER TIME_UNITS="milliseconds">
    <MEDIA_DESCRIPTOR MEDIA_URL="audio.wav" MIME_TYPE="audio/x-wav" />
  </HEADER>
  <TIME_ORDER>
    <TIME_SLOT TIME_SLOT_ID="start" TIME_VALUE="1250" />
    <TIME_SLOT TIME_SLOT_ID="end" TIME_VALUE="3250" />
    <TIME_SLOT TIME_SLOT_ID="next" TIME_VALUE="5000" />
  </TIME_ORDER>
  <TIER TIER_ID="Transcription" LINGUISTIC_TYPE_REF="Transcription">
    <ANNOTATION>
      <ALIGNABLE_ANNOTATION ANNOTATION_ID="utterance-1"
          TIME_SLOT_REF1="start" TIME_SLOT_REF2="end">
        <ANNOTATION_VALUE>Hēsci! Hiyowat.</ANNOTATION_VALUE>
      </ALIGNABLE_ANNOTATION>
    </ANNOTATION>
    <ANNOTATION>
      <ALIGNABLE_ANNOTATION ANNOTATION_ID="utterance-2"
          TIME_SLOT_REF1="end" TIME_SLOT_REF2="next">
        <ANNOTATION_VALUE>Second sentence.</ANNOTATION_VALUE>
      </ALIGNABLE_ANNOTATION>
    </ANNOTATION>
  </TIER>
  <TIER TIER_ID="Phrase Free Translation" LINGUISTIC_TYPE_REF="Translation"
      PARENT_REF="Transcription">
    <ANNOTATION>
      <REF_ANNOTATION ANNOTATION_ID="translation-1"
          ANNOTATION_REF="utterance-1">
        <ANNOTATION_VALUE>Hello! Again today.</ANNOTATION_VALUE>
      </REF_ANNOTATION>
    </ANNOTATION>
  </TIER>
</ANNOTATION_DOCUMENT>
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
        ${List.generate(30, (index) => '<p><s id="sentence-$index">Paragraph $index with enough text to fill the page and continue scrolling.</s></p>').join()}
      </div>
    </body>
  </text>
</read-along>
''';

final _alignedLongPageXml =
    '''
<read-along>
  <text xml:lang="eng">
    <body>
      <div type="page" id="long-page">
        ${List.generate(20, (index) => '<p><s id="sentence-$index"><w id="word-$index" time="${index * 2}" dur="1">Paragraph $index with enough text to fill the page and continue scrolling.</w></s></p>').join()}
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

  test('external playback controller drives aligned reader playback', () async {
    final controller = _TestPlaybackController();
    final manager = Manager(
      xml: _sampleXml,
      xmlAsset: null,
      audioSource: null,
      playbackController: controller,
    );

    await manager.initialize();
    expect(manager.duration, controller.duration);

    await manager.play();
    expect(controller.playCount, 1);

    controller.emitPosition(const Duration(milliseconds: 500));
    expect(manager.activeWordId, 'word-1');

    await manager.replay();
    expect(controller.pauseCount, 1);
    expect(controller.seekPositions, [Duration.zero]);
    expect(controller.playCount, 2);

    manager.dispose();
    expect(controller.isClosed, isFalse);
    await controller.dispose();
  });

  test(
    'autoplay pauses and turns page halfway through the inter-page gap',
    () async {
      final controller = _TestPlaybackController();
      final manager = Manager(
        xml: _twoAlignedPageXml,
        xmlAsset: null,
        audioSource: null,
        playbackController: controller,
      );
      addTearDown(manager.dispose);
      addTearDown(controller.dispose);
      await manager.initialize();

      expect(
        manager.pageIndexForPosition(const Duration(milliseconds: 2999)),
        0,
      );
      expect(manager.pageIndexForPosition(const Duration(seconds: 3)), 1);

      manager.togglePagePlaybackMode();
      await manager.play();
      controller.emitPosition(const Duration(seconds: 2));
      expect(manager.isPlaying, isTrue);
      expect(controller.pauseCount, 0);

      controller.emitPosition(const Duration(seconds: 3));
      await Future<void>.delayed(Duration.zero);

      expect(manager.isPlaying, isFalse);
      expect(manager.position, const Duration(seconds: 3));
      expect(controller.seekPositions, [const Duration(seconds: 3)]);
    },
  );

  test(
    'external playback controller restores initial position and active word',
    () async {
      final controller = _TestPlaybackController(
        initialPosition: const Duration(milliseconds: 800),
      );
      final manager = Manager(
        xml: _sampleXml,
        xmlAsset: null,
        audioSource: null,
        playbackController: controller,
      );
      addTearDown(manager.dispose);

      await manager.initialize();
      expect(manager.position, const Duration(milliseconds: 800));
      expect(manager.activeWordId, 'word-2');
    },
  );

  test('external playback state mirrors JustAudio state transitions', () async {
    final controller = _TestPlaybackController();
    final manager = Manager(
      xml: _sampleXml,
      xmlAsset: null,
      audioSource: null,
      playbackController: controller,
    );
    addTearDown(manager.dispose);
    await manager.initialize();

    controller.emitState(PlayerState(false, ProcessingState.loading));
    expect(manager.buttonState.value, ButtonState.pausedLoading);
    expect(manager.isAudioLoading, isTrue);

    controller.emitState(PlayerState(true, ProcessingState.buffering));
    expect(manager.buttonState.value, ButtonState.playingLoading);
    expect(manager.isAudioLoading, isTrue);
    expect(manager.isPlaying, isTrue);

    controller.emitState(PlayerState(true, ProcessingState.ready));
    expect(manager.buttonState.value, ButtonState.playing);
    expect(manager.isAudioLoading, isFalse);

    controller.emitState(PlayerState(false, ProcessingState.completed));
    expect(manager.buttonState.value, ButtonState.completed);
    expect(manager.isCompleted, isTrue);
    expect(manager.isPlaying, isFalse);

    controller.emitState(PlayerState(false, ProcessingState.ready));
    expect(manager.buttonState.value, ButtonState.paused);
    expect(manager.isCompleted, isFalse);
  });

  testWidgets('external player hides reader controls and syncs text', (
    tester,
  ) async {
    final controller = _TestPlaybackController();
    final positions = <ReadAlongPosition>[];

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 500,
          child: ReadAlong(
            xml: _sampleXml,
            playbackController: controller,
            onPositionChanged: positions.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AudioPlayerWidget), findsNothing);
    expect(find.textContaining('Hello'), findsOneWidget);

    controller.emitPosition(const Duration(milliseconds: 500));
    await tester.pump();

    expect(positions.last.audioPosition, const Duration(milliseconds: 500));
    expect(positions.last.activeWordId, 'word-1');

    await tester.pumpWidget(const SizedBox.shrink());
    expect(controller.isClosed, isFalse);
    await controller.dispose();
  });

  testWidgets(
    'swiping back to the first page is not overridden by playback position',
    (tester) async {
      final controller = _TestPlaybackController(
        initialPosition: const Duration(seconds: 5),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 500,
            child: ReadAlong(
              xml: _twoAlignedPageXml,
              playbackController: controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pageController = tester
          .widget<PageView>(find.byType(PageView))
          .controller!;
      expect(pageController.page, closeTo(1, 0.01));

      await tester.drag(find.byType(PageView), const Offset(500, 0));
      await tester.pumpAndSettle();

      expect(pageController.page, closeTo(0, 0.01));
    },
  );

  testWidgets('scrubbing follows the highlighted word across pages', (
    tester,
  ) async {
    final controller = _TestPlaybackController(
      duration: const Duration(seconds: 10),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 500,
          child: ReadAlong(
            xml: _twoAlignedPageXml,
            playbackController: controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final manager = tester.widget<ReaderPage>(find.byType(ReaderPage)).manager;
    final pageController = tester
        .widget<PageView>(find.byType(PageView))
        .controller!;
    await manager.beginSeek();
    manager.updateSeekPreviewMilliseconds(5000);
    await tester.pumpAndSettle();

    expect(manager.activeWordId, 'word-2');
    expect(pageController.page, closeTo(1, 0.01));

    manager.updateSeekPreviewMilliseconds(0);
    await tester.pumpAndSettle();

    expect(manager.activeWordId, 'word-1');
    expect(pageController.page, closeTo(0, 0.01));
  });

  testWidgets('playing after swiping starts at the selected page', (
    tester,
  ) async {
    final controller = _TestPlaybackController(
      duration: const Duration(seconds: 10),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 500,
          child: ReadAlong(
            xml: _twoAlignedPageXml,
            playbackController: controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final manager = tester
        .widgetList<ReaderPage>(find.byType(ReaderPage))
        .first
        .manager;
    final pageView = find.byType(PageView);

    await tester.drag(pageView, const Offset(-500, 0));
    await tester.pumpAndSettle();
    await manager.play();
    await tester.pumpAndSettle();

    expect(controller.seekPositions, [const Duration(seconds: 5)]);

    await manager.pause();
    await tester.pumpAndSettle();
    await tester.drag(pageView, const Offset(500, 0));
    await tester.pumpAndSettle();
    await manager.play();
    await tester.pumpAndSettle();

    expect(controller.seekPositions, [
      const Duration(seconds: 5),
      Duration.zero,
    ]);
  });

  test(
    'seek preview updates the highlighted word without committing position',
    () async {
      final manager = Manager(
        xml: _sampleXml,
        xmlAsset: null,
        audioSource: null,
      );
      addTearDown(manager.dispose);
      await manager.initialize();

      await manager.beginSeek();
      manager.updateSeekPreviewMilliseconds(900);

      expect(manager.displayPosition, const Duration(milliseconds: 900));
      expect(manager.position, Duration.zero);
      expect(manager.activeWordId, 'word-2');
    },
  );

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
    final changedSpeeds = <double>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: AudioPlayerWidget(
              manager: manager,
              onSpeedChanged: changedSpeeds.add,
            ),
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
    expect(changedSpeeds, contains(1.5));
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
    final titleColor = tester
        .widget<Text>(find.text('Speaker name'))
        .style
        ?.color;
    expect(
      tester.widget<Icon>(find.byIcon(Icons.info_outline)).color,
      titleColor,
    );
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

  testWidgets('autoplay toggle switches between auto and pause-at-page modes', (
    tester,
  ) async {
    final manager = Manager(xml: _sampleXml, xmlAsset: null, audioSource: null);
    addTearDown(manager.dispose);
    final autoplayChanges = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AudioPlayerWidget(
            manager: manager,
            canGoToNextPage: true,
            onAutoplayChanged: autoplayChanges.add,
          ),
        ),
      ),
    );

    expect(manager.autoplay, isTrue);
    expect(find.byTooltip('Autoplay On'), findsOneWidget);

    await tester.tap(find.byTooltip('Autoplay On'));
    await tester.pump();

    expect(manager.autoplay, isFalse);
    expect(autoplayChanges, [false]);
    expect(find.byTooltip('Autoplay Off'), findsOneWidget);
    expect(find.text('Autoplay off'), findsOneWidget);

    await tester.tap(find.byTooltip('Autoplay Off'));
    await tester.pump();

    expect(manager.autoplay, isTrue);
    expect(autoplayChanges, [false, true]);
    expect(find.byTooltip('Autoplay On'), findsOneWidget);
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

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/images/example01.jpg',
    );
    expect(image.fit, BoxFit.cover);
    expect(
      tester.getSize(find.byType(Image)).height,
      greaterThanOrEqualTo(200),
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

      final audioSource = just_audio.AudioSource.asset('missing-audio.mp3');
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

      await tester.drag(
        find.byType(CustomScrollView).hitTestable().first,
        const Offset(0, -700),
      );
      await tester.pumpAndSettle();
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
      await tester.drag(
        find.byType(CustomScrollView).hitTestable().first,
        const Offset(0, -700),
      );
      await tester.pumpAndSettle();

      expect(find.text('First page words'), findsNothing);
      expect(find.byType(Image), findsOneWidget);
      expect(
        (tester.widget<Image>(find.byType(Image)).image as AssetImage)
            .assetName,
        'assets/images/second.jpg',
      );
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
      await tester.drag(
        find.byType(CustomScrollView).hitTestable().first,
        const Offset(0, -700),
      );
      await tester.pumpAndSettle();
      expect(find.text('First page words'), findsOneWidget);

      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(
        (tester.widget<Image>(find.byType(Image)).image as AssetImage)
            .assetName,
        'assets/images/second.jpg',
      );
    },
  );

  testWidgets('page image is capped at half the viewport and collapses', (
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
    final scrollView = find.byType(CustomScrollView);
    final image = find.byType(Image);
    final initialImageHeight = tester.getSize(image).height;
    expect(initialImageHeight, greaterThan(200));
    expect(initialImageHeight, lessThanOrEqualTo(500));

    await tester.drag(scrollView, const Offset(0, -300));
    await tester.pumpAndSettle();

    final collapsedImageHeight = tester.getSize(image).height;
    expect(collapsedImageHeight, lessThan(initialImageHeight));
    expect(collapsedImageHeight, greaterThanOrEqualTo(200));

    await tester.drag(scrollView, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.getSize(image).height, 200);
  });

  testWidgets('page image fits within half of a short viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(200, 300)),
          child: const ReadAlong(xml: _imageXml, imagesFolder: 'assets/images'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(Image)).height, lessThanOrEqualTo(150));
  });

  testWidgets('image and text use two columns in compact landscape', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final manager = Manager(xml: _imageXml, xmlAsset: null, audioSource: null);
    await manager.initialize();
    addTearDown(manager.dispose);
    var backgroundTapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: ReaderPage(
            page: manager.document!.pages.single,
            manager: manager,
            imageUri: 'missing-image.jpg',
            onBackgroundTap: () => backgroundTapCount++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final imageRect = tester.getRect(find.byType(Image));
    final textRect = tester.getRect(find.text('Story text'));
    expect(imageRect.height, lessThanOrEqualTo(250));
    expect(imageRect.right, lessThanOrEqualTo(textRect.left));
    expect(tester.getSize(find.byType(CustomScrollView)).width, lessThan(700));

    await tester.tapAt(textRect.center);
    await tester.pump();
    expect(backgroundTapCount, 0);

    await tester.tapAt(imageRect.center);
    await tester.pump();
    final textViewportRect = tester.getRect(find.byType(CustomScrollView));
    await tester.tapAt(
      Offset(textViewportRect.center.dx, textViewportRect.bottom - 12),
    );
    await tester.pump();
    expect(backgroundTapCount, 2);
  });

  testWidgets('portrait image and blank text area trigger background tap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final manager = Manager(xml: _imageXml, xmlAsset: null, audioSource: null);
    await manager.initialize();
    addTearDown(manager.dispose);
    var backgroundTapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: ReaderPage(
            page: manager.document!.pages.single,
            manager: manager,
            imageUri: 'missing-image.jpg',
            onBackgroundTap: () => backgroundTapCount++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(tester.getRect(find.byType(Image)).center);
    await tester.pump();
    expect(backgroundTapCount, 1);

    final textViewport = tester.getRect(find.byType(CustomScrollView));
    await tester.tapAt(
      Offset(textViewport.center.dx, textViewport.bottom - 12),
    );
    await tester.pump();
    expect(backgroundTapCount, 2);
  });

  testWidgets(
    'active sentence scrolls near the top during progress scrubbing',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final manager = Manager(
        xml: _alignedLongPageXml,
        xmlAsset: null,
        audioSource: null,
      );
      await manager.initialize();
      addTearDown(manager.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 700,
            child: ReaderPage(
              page: manager.document!.pages.single,
              manager: manager,
              imageUri: 'missing-image.jpg',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await manager.beginSeek();
      manager.updateSeekPreviewMilliseconds(10500);
      await tester.pumpAndSettle();

      final scrollState = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        ),
      );
      final viewportTop = tester.getTopLeft(find.byType(CustomScrollView)).dy;
      final sentenceTop = tester
          .getTopLeft(
            find.text(
              'Paragraph 5 with enough text to fill the page and continue scrolling.',
            ),
          )
          .dy;
      expect(manager.activeWordId, 'word-5');
      expect(scrollState.position.pixels, greaterThan(0));
      expect(tester.getSize(find.byType(Image)).height, closeTo(200, 2));
      expect(sentenceTop, closeTo(viewportTop + 216, 2));
    },
  );

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

  test(
    'replay after completion returns the player to the playing state',
    () async {
      final player = _CompletedReplayAudioPlayer();
      final manager = Manager(
        xml: _sampleXml,
        xmlAsset: null,
        audioSource: null,
        audioPlayer: player,
      );
      addTearDown(() async {
        manager.dispose();
        await player.close();
        await player.dispose();
      });

      await manager.initialize();
      player.complete();
      expect(manager.buttonState.value, ButtonState.completed);

      await manager.replay();

      expect(player.commands, ['pause', 'seek', 'play']);
      expect(manager.buttonState.value, ButtonState.playing);
    },
  );

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

    test('parses ELAN transcription and linked translation timings', () {
      final document = ReadAlongDocument.fromXml(_elanXml);
      final firstParagraph = document.pages.single.paragraphs.first;
      final transcription = firstParagraph.sentences.first;
      final translation = firstParagraph.sentences.last;
      final timedSentence = transcription.segments.single as ReadAlongWord;

      expect(document.pages, hasLength(1));
      expect(document.pages.single.imageUrl, isNull);
      expect(document.metadata['author'], 'Test author');
      expect(transcription.id, 'utterance-1');
      expect(timedSentence.id, 'utterance-1');
      expect(timedSentence.text, 'Hēsci! Hiyowat.');
      expect(timedSentence.start, const Duration(milliseconds: 1250));
      expect(timedSentence.duration, const Duration(milliseconds: 2000));
      expect(translation.isTranslation, isTrue);
      expect(translation.segments.single.text, 'Hello! Again today.');
      expect(document.pages.single.paragraphs, hasLength(2));
      expect(
        (document.pages.single.paragraphs.last.sentences.first.segments.single
                as ReadAlongWord)
            .start,
        const Duration(milliseconds: 3250),
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
    'reports text bookmark position and sends a final dispose value',
    (tester) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final positions = <ReadAlongPosition>[];
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 600,
            child: ReadAlong(
              xml: _longPageXml,
              onPositionChanged: positions.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(positions, isNotEmpty);
      expect(positions.last.pageIndex, 0);
      expect(positions.last.audioPosition, isNull);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(positions.last.textScrollOffset, greaterThan(0));

      final lastPositionBeforeDispose = positions.length;
      await tester.pumpWidget(const SizedBox.shrink());
      expect(positions, hasLength(lastPositionBeforeDispose + 1));
      expect(positions.last.textScrollOffset, greaterThan(0));
    },
  );

  testWidgets('reader hides system UI in landscape and restores it afterward', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final systemUiCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          systemUiCalls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    tester.view.physicalSize = const Size(1000, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: ReadAlong(xml: _sampleXml)),
    );
    await tester.pumpAndSettle();

    expect(
      systemUiCalls,
      contains(
        isA<MethodCall>()
            .having(
              (call) => call.method,
              'method',
              'SystemChrome.setEnabledSystemUIMode',
            )
            .having(
              (call) => call.arguments,
              'mode',
              'SystemUiMode.immersiveSticky',
            ),
      ),
    );

    tester.view.physicalSize = const Size(500, 1000);
    await tester.pumpAndSettle();

    expect(
      systemUiCalls,
      contains(
        isA<MethodCall>()
            .having(
              (call) => call.method,
              'method',
              'SystemChrome.setEnabledSystemUIMode',
            )
            .having(
              (call) => call.arguments,
              'mode',
              'SystemUiMode.edgeToEdge',
            ),
      ),
    );

    tester.view.physicalSize = const Size(1000, 500);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(
      systemUiCalls
          .where(
            (call) =>
                call.method == 'SystemChrome.setEnabledSystemUIMode' &&
                call.arguments == 'SystemUiMode.edgeToEdge',
          )
          .length,
      2,
    );
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

class _CompletedReplayAudioPlayer extends just_audio.AudioPlayer {
  _CompletedReplayAudioPlayer() : super(handleInterruptions: false);

  final StreamController<just_audio.PlayerState> _playerStates =
      StreamController<just_audio.PlayerState>.broadcast(sync: true);
  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast(sync: true);
  final List<String> commands = [];
  bool _isPlaying = false;
  just_audio.ProcessingState _processingState = just_audio.ProcessingState.idle;

  @override
  Stream<just_audio.PlayerState> get playerStateStream => _playerStates.stream;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  double get speed => 1;

  void complete() {
    _isPlaying = true;
    _processingState = just_audio.ProcessingState.completed;
    _playerStates.add(just_audio.PlayerState(_isPlaying, _processingState));
  }

  @override
  Future<void> pause() async {
    commands.add('pause');
    _isPlaying = false;
    _playerStates.add(just_audio.PlayerState(_isPlaying, _processingState));
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    commands.add('seek');
    if (!_isPlaying &&
        _processingState == just_audio.ProcessingState.completed) {
      _processingState = just_audio.ProcessingState.ready;
    }
    _positions.add(position ?? Duration.zero);
    _playerStates.add(just_audio.PlayerState(_isPlaying, _processingState));
  }

  @override
  Future<void> play() async {
    commands.add('play');
    if (_isPlaying) return;
    _isPlaying = true;
    _playerStates.add(just_audio.PlayerState(_isPlaying, _processingState));
  }

  Future<void> close() async {
    await _playerStates.close();
    await _positions.close();
  }
}

class _TestPlaybackController implements PlaybackController {
  _TestPlaybackController({
    Duration initialPosition = Duration.zero,
    this.duration = const Duration(seconds: 2),
  }) : _position = initialPosition;

  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast(sync: true);
  final StreamController<Duration?> _durations =
      StreamController<Duration?>.broadcast(sync: true);
  final StreamController<PlayerState> _states =
      StreamController<PlayerState>.broadcast(sync: true);
  final List<Duration> seekPositions = [];

  Duration _position = Duration.zero;
  @override
  final Duration duration;
  PlayerState _state = PlayerState(false, ProcessingState.ready);
  int playCount = 0;
  int pauseCount = 0;

  bool get isClosed =>
      _positions.isClosed || _durations.isClosed || _states.isClosed;

  @override
  Duration get position => _position;

  @override
  double get speed => 1;

  @override
  PlayerState get state => _state;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<Duration?> get durationStream => _durations.stream;

  @override
  Stream<PlayerState> get stateStream => _states.stream;

  void emitState(PlayerState state) {
    _state = state;
    _states.add(state);
  }

  void emitPosition(Duration position) {
    _position = position;
    _positions.add(position);
  }

  @override
  Future<void> play() async {
    playCount++;
    emitState(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    emitState(PlayerState(false, ProcessingState.ready));
  }

  @override
  Future<void> stop() async {
    await pause();
    await seek(Duration.zero);
  }

  @override
  Future<void> seek(Duration position) async {
    seekPositions.add(position);
    emitPosition(position);
  }

  @override
  Future<void> setSpeed(double speed) async {}

  Future<void> dispose() async {
    await _positions.close();
    await _durations.close();
    await _states.close();
  }
}
