import 'package:flutter/material.dart';
import 'package:readalong/components/speed_dialog.dart';

import '../manager.dart';

class AudioPlayerWidget extends StatelessWidget {
  const AudioPlayerWidget({
    super.key,
    required this.manager,
    this.title,
    this.onPreviousPage,
    this.onNextPage,
    this.canGoToPreviousPage = false,
    this.canGoToNextPage = false,
  });

  final Manager manager;
  final String? title;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;
  final bool canGoToPreviousPage;
  final bool canGoToNextPage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null && title!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                title!,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          _buildProgressSlider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildTimestamps(context),
          ),
          SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(width: 60),
                IconButton(
                  tooltip: 'Previous page',
                  onPressed: canGoToPreviousPage ? onPreviousPage : null,
                  icon: const Icon(Icons.skip_previous),
                ),
                Center(child: PlayButton(manager: manager)),
                IconButton(
                  tooltip: 'Next page',
                  onPressed: canGoToNextPage ? onNextPage : null,
                  icon: const Icon(Icons.skip_next),
                ),
                SizedBox(width: 60, child: SpeedDialog(manager: manager)),
              ],
            ),
          ),
        ],
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
        : manager.position.inMilliseconds
              .clamp(0, totalMilliseconds)
              .toDouble();

    return Slider(
      value: value,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      max: totalMilliseconds > 0 ? totalMilliseconds.toDouble() : 1,
      onChanged: totalMilliseconds == 0 || manager.isAudioLoading
          ? null
          : manager.seekMilliseconds,
    );
  }

  Widget _buildTimestamps(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(_formatDuration(manager.position), style: style),
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
  const PlayButton({super.key, required this.manager});
  final Manager manager;

  @override
  Widget build(BuildContext context) {
    double size = 32.0;
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
              onPressed: manager.replay,
            );
          case ButtonState.paused:
            return IconButton(
              tooltip: 'Play',
              icon: const Icon(Icons.play_arrow),
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
