import 'package:flutter/material.dart';
import 'package:readalong/components/speed_dialog.dart';

import '../manager.dart';

class AudioPlayerWidget extends StatelessWidget {
  const AudioPlayerWidget({super.key, required this.manager});

  final Manager manager;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        PlayButton(manager: manager),
        Expanded(child: _buildProgressBar()),
        SpeedDialog(manager: manager),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildProgressBar() {
    final totalMilliseconds = manager.duration?.inMilliseconds ?? 0;
    final value = totalMilliseconds == 0
        ? 0.0
        : manager.position.inMilliseconds
              .clamp(0, totalMilliseconds)
              .toDouble();

    return Row(
      children: [
        Text(_formatDuration(manager.position)),
        Expanded(
          child: Slider(
            value: value,
            max: totalMilliseconds > 0 ? totalMilliseconds.toDouble() : 1,
            onChanged: totalMilliseconds == 0 || manager.isAudioLoading
                ? null
                : manager.seekMilliseconds,
          ),
        ),
        Text(
          manager.duration == null
              ? '--:--'
              : _formatDuration(manager.duration!),
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
