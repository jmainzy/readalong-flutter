import 'package:flutter/material.dart';

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
        AnimatedBuilder(
          animation: manager,
          builder: (context, _) => Builder(
            builder: (buttonContext) => IconButton(
              tooltip: 'Adjust speed',
              icon: Text(
                '${manager.speed.toStringAsFixed(1)}x',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () => showSliderDialog(
                context: buttonContext,
                manager: manager,
              ),
            ),
          ),
        ),
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

Future<void> showSliderDialog({
  required BuildContext context,
  required Manager manager,
}) async {
  const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  const itemHeight = 36.0;
  const menuVerticalPadding = 16.0;

  final button = context.findRenderObject()! as RenderBox;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final buttonTopLeft = button.localToGlobal(
    Offset.zero,
    ancestor: overlay,
  );
  final buttonBottomRight = button.localToGlobal(
    button.size.bottomRight(Offset.zero),
    ancestor: overlay,
  );
  final buttonRect = Rect.fromPoints(buttonTopLeft, buttonBottomRight);
  final menuHeight = speeds.length * itemHeight + menuVerticalPadding;
  final menuTop = (buttonRect.top - menuHeight).clamp(
    0.0,
    overlay.size.height,
  );

  final selectedSpeed = await showMenu<double>(
    context: context,
    position: RelativeRect.fromLTRB(
      buttonRect.left,
      menuTop,
      overlay.size.width - buttonRect.right,
      overlay.size.height - buttonRect.top,
    ),
    items: [
      for (final speed in speeds)
        PopupMenuItem<double>(
          value: speed,
          height: itemHeight,
          child: Text('${_formatSpeed(speed)}x'),
        ),
    ],
  );
  if (selectedSpeed != null) await manager.setSpeed(selectedSpeed);
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

String _formatSpeed(double speed) {
  return speed == speed.roundToDouble()
      ? speed.toStringAsFixed(0)
      : speed.toString();
}
