# Readalong Flutter component

A Flutter library for displaying a [ReadAlong Studio](https://github.com/ReadAlongs/Studio) `.readalong` document with word-level audio alignment.

This is just a widget, you'll need to import it into a full Flutter app yourself.

![example](readalong_screenshot.png)

## Features

- Parse ReadAlong XML into pages, paragraphs, sentences, aligned words, and metadata.
- Play an audio source, seek by tapping aligned words, and highlight the word at the current playback position.
- Load XML directly or from a Flutter asset.

## Install

Add `readalong` to your Flutter project's dependencies `pubspec.yaml`, by referencing this repo:

```
readalong:
  git:
    url: https://github.com/jmainzy/readalong-flutter.git
```

Alternatively, clone the repo and reference the location in your pubspec:

```
readalong:
  path: ../readalong
```

## Usage

First, [make a Readalong](https://readalong-studio.mothertongues.org/#/), and then download it as "Offline HTML".

Open the html bundle and find the file that ends in `.readalong` and the audio.  Put those into the assets directory in your Flutter app, and reference them in the component:

```dart
ReadAlong(
  xmlAsset: 'assets/story.readalong',
  audioSource: AudioSource.asset('assets/story.mp3'),
)
```

 You can also load the XML yourself and pass it as `xml`:

```dart
final xml = await rootBundle.loadString('assets/story.readalong');

ReadAlong(
  xml: xml,
  audioSource: AudioSource.asset('assets/story.mp3'),
)
```

## Full API

| Option                 | Type                               | Default | Description                                                                                                                                                                                            |
| ---------------------- | ---------------------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `key`                  | `Key?`                             | —       | Standard Flutter widget key.                                                                                                                                                                           |
| `xml`                  | `String?`                          | `null`  | ReadAlong XML content supplied directly. Provide exactly one of `xml` or `xmlAsset`.                                                                                                                   |
| `xmlAsset`             | `String?`                          | `null`  | Asset path to a `.readalong` XML file. Provide exactly one of `xml` or `xmlAsset`.                                                                                                                     |
| `imagesFolder`         | `String?`                          | `null`  | Asset folder for page images referenced by the XML. For example, `assets/images` resolves `page1.jpg` to `assets/images/page1.jpg`.                                                                    |
| `audioSource`          | `AudioSource?`                     | `null`  | Optional `just_audio` source. When omitted, playback controls and interactive word playback are disabled.                                                                                              |
| `audioTitle`           | `String?`                          | `null`  | Optional title, such as the reader or performer, shown with the audio controls.                                                                                                                        |
| `onAutoplayChanged`    | `ValueChanged<bool>?`              | `null`  | Called when the user changes autoplay between pages.                                                                                                                                                   |
| `onSpeedChanged`       | `ValueChanged<double>?`            | `null`  | Called when the user changes playback speed; receives the speed multiplier.                                                                                                                            |
| `onReaderSurfaceTap`   | `VoidCallback?`                    | `null`  | Called when the reader's image or blank text area is tapped.                                                                                                                                           |
| `onPositionChanged`    | `ValueChanged<ReadAlongPosition>?` | `null`  | Receives reading-position updates and a final snapshot immediately before disposal. The snapshot contains page ID/index, text scroll offset, active word ID, and audio position when audio is enabled. |
| `showTranslations`     | `bool`                             | `true`  | Whether to show translation sentences marked with `class="translation"`.                                                                                                                               |
| `textStyle`            | `TextStyle?`                       | `null`  | Optional style for the main document text. Uses the theme's larger body style by default.                                                                                                              |
| `translationTextStyle` | `TextStyle?`                       | `null`  | Optional style for translations. Uses smaller, lighter grey text by default.                                                                                                                           |
| `highlightColor`       | `Color?`                           | `null`  | Background color for the word currently being spoken. Defaults to the theme's primary container color.                                                                                                 |
### Fullscreen

On Android and iOS, the reader hides the system bars while the device is in
landscape and restores the normal edge-to-edge system UI when returning to
portrait or when the reader is removed.

Example:

```dart
ReadAlong(
  xmlAsset: 'assets/story.readalong',
  audioSource: AudioSource.asset('assets/story.mp3'),
  onAutoplayChanged: (enabled) => saveAutoplaySetting(enabled),
  onSpeedChanged: (speed) => savePlaybackSpeed(speed),
)
```


## Parsing XML without the widget

```dart
final document = ReadAlongDocument.fromXml(xml);

for (final word in document.words) {
  if (word.isAligned) {
    print('${word.text}: ${word.start} + ${word.duration}');
  }
}
```

## Scope

This package implements the reusable reading/playback experience. The web component's editing tools, annotation controls, persistent user preferences, and custom SVG progress overlays are not part of this initial Flutter library.
