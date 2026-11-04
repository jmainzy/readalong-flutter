# readalong

A Flutter library for displaying [ReadAlong Studio](https://github.com/ReadAlongs/Studio) `.readalong` XML with word-level audio alignment.

## Features

- Parse ReadAlong XML into pages, paragraphs, sentences, aligned words, and metadata.
- Display the document as a Flutter widget.
- Play an audio source, seek by tapping aligned words, and highlight the word at the current playback position.
- Load XML directly or from a Flutter asset.
- Optionally hide translation sentences marked with `class="translation"`.

## Getting started

Add `readalong` to your Flutter project's dependencies, then import:

```dart
import 'package:just_audio/just_audio.dart';
import 'package:readalong/readalong.dart';
```

Provide the XML content (or an asset path) and an audio source:

```dart
ReadAlong(
  xmlAsset: 'assets/story.readalong',
  audioSource: AudioSource.asset('assets/story.mp3'),
)
```

Declare both files in the consuming app's `pubspec.yaml`. You can also load the XML yourself and pass it as `xml`:

```dart
import 'package:just_audio/just_audio.dart';
import 'package:flutter/services.dart';
import 'package:readalong/readalong.dart';

final xml = await rootBundle.loadString('assets/story.readalong');

ReadAlong(
  xml: xml,
  audioSource: AudioSource.asset('assets/story.mp3'),
)
```

`audioSource` is optional; without it, the widget displays the document without playback controls or interactive words. `just_audio` sources such as `AudioSource.uri(...)` can be used for remote audio.

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
