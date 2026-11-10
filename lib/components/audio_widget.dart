import 'dart:async';

import 'package:flutter/material.dart';
import 'package:readalong/components/speed_dialog.dart';

import '../manager.dart';

class AudioPlayerWidget extends StatelessWidget {
  const AudioPlayerWidget({
    super.key,
    required this.manager,
    this.title,
    this.onAutoplayChanged,
    this.onSpeedChanged,
    this.onPreviousPage,
    this.onNextPage,
    this.onReplay,
    this.canGoToPreviousPage = false,
    this.canGoToNextPage = false,
  });

  final Manager manager;
  final String? title;
  final ValueChanged<bool>? onAutoplayChanged;
  final ValueChanged<double>? onSpeedChanged;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;
  final VoidCallback? onReplay;
  final bool canGoToPreviousPage;
  final bool canGoToNextPage;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).textTheme.labelMedium?.color?.withAlpha(120),
    );
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildProgressSlider(),
            ),
            if (MediaQuery.orientationOf(context) == Orientation.portrait)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildTimestamps(context),
              )
            else
              Container(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Visibility(
                  visible: canGoToPreviousPage || canGoToNextPage,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: AnimatedBuilder(
                    animation: manager,
                    builder: (context, _) {
                      final autoplay = manager.autoplay;
                      return IconButton(
                        tooltip: autoplay ? 'Autoplay On' : 'Autoplay Off',
                        onPressed: () {
                          manager.togglePagePlaybackMode();
                          onAutoplayChanged?.call(manager.autoplay);
                          final screenWidth = MediaQuery.of(context).size.width;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              behavior: SnackBarBehavior.floating,
                              margin: EdgeInsets.fromLTRB(
                                screenWidth * 0.01,
                                0,
                                screenWidth * 0.6,
                                126,
                              ),
                              content: Text(
                                'Autoplay ${manager.autoplay ? 'on' : 'off'}',
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: Icon(Icons.rotate_right),
                        color: autoplay
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      );
                    },
                  ),
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Visibility(
                        visible: canGoToPreviousPage,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: IconButton(
                          tooltip: 'Previous page',
                          onPressed: canGoToPreviousPage
                              ? onPreviousPage
                              : null,
                          icon: const Icon(Icons.chevron_left),
                        ),
                      ),
                      PlayButton(manager: manager, onReplay: onReplay),

                      Visibility(
                        visible: canGoToNextPage,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: IconButton(
                          tooltip: 'Next page',
                          onPressed: canGoToNextPage ? onNextPage : null,
                          icon: const Icon(Icons.chevron_right_sharp),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: SpeedButton(
                    manager: manager,
                    onSpeedChanged: onSpeedChanged,
                  ),
                ),
              ],
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (MediaQuery.orientationOf(context) == Orientation.portrait &&
                    title != null &&
                    title!.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 14),
                      Icon(
                        Icons.info_outline,
                        color: titleStyle?.color,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(title!, style: titleStyle),
                    ],
                  )
                else
                  const SizedBox.shrink(),
              ],
            ),
            SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildProgressSlider() {
    final totalMilliseconds = manager.duration?.inMilliseconds ?? 0;
    final value = totalMilliseconds == 0
        ? 0.0
        : manager.displayPosition.inMilliseconds
              .clamp(0, totalMilliseconds)
              .toDouble();

    return Slider(
      value: value,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      max: totalMilliseconds > 0 ? totalMilliseconds.toDouble() : 1,
      onChangeStart: totalMilliseconds == 0 || manager.isAudioLoading
          ? null
          : (_) => unawaited(manager.beginSeek()),
      onChanged: totalMilliseconds == 0 || manager.isAudioLoading
          ? null
          : manager.updateSeekPreviewMilliseconds,
      onChangeEnd: totalMilliseconds == 0 || manager.isAudioLoading
          ? null
          : manager.endSeek,
    );
  }

  Widget _buildTimestamps(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(_formatDuration(manager.displayPosition), style: style),
        Text(
          manager.duration == null
              ? '--:--'
              : _formatDuration(manager.duration!),
          style: style,
        ),
      ],
    );
  }
}

class PlayButton extends StatelessWidget {
  const PlayButton({super.key, required this.manager, this.onReplay});
  final Manager manager;
  final VoidCallback? onReplay;

  @override
  Widget build(BuildContext context) {
    double size = 42.0;
    return ValueListenableBuilder<ButtonState>(
      valueListenable: manager.buttonState,
      builder: (context, value, _) {
        switch (value) {
          case ButtonState.playingLoading:
          case ButtonState.pausedLoading:
            return Container(
              margin: const EdgeInsets.all(8.0),
              width: size,
              height: size,
              child: const CircularProgressIndicator(),
            );
          case ButtonState.completed:
            return IconButton(
              tooltip: 'Replay',
              icon: const Icon(Icons.replay),
              iconSize: size,
              onPressed: () {
                onReplay?.call();
                manager.replay();
              },
            );
          case ButtonState.paused:
            return IconButton(
              tooltip: 'Play',
              icon: const Icon(Icons.play_circle_fill),
              iconSize: size,
              onPressed: manager.play,
            );
          case ButtonState.playing:
            return IconButton(
              tooltip: 'Pause',
              icon: const Icon(Icons.pause),
              iconSize: size,
              onPressed: manager.pause,
            );
        }
      },
    );
  }
}
