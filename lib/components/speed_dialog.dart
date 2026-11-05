import 'package:flutter/material.dart';
import 'package:readalong/manager.dart';

class SpeedDialog extends StatefulWidget {
  final Manager manager;

  const SpeedDialog({super.key, required this.manager});
  @override
  State<SpeedDialog> createState() => _SpeedDialogState();
}

class _SpeedDialogState extends State<SpeedDialog> {
  static const speeds = [0.3, 0.5, 0.8, 1.0, 1.2, 1.5, 1.7];
  final FocusNode _buttonFocusNode = FocusNode(debugLabel: 'Speed Button');

  int _speedIndex(double speed) {
    return speeds.indexOf(
      speeds.reduce(
        (closest, option) =>
            (option - speed).abs() < (closest - speed).abs() ? option : closest,
      ),
    );
  }

  @override
  void dispose() {
    _buttonFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.manager,
      builder: (context, _) => SizedBox(
        width: 60,
        height: 48,
        child: MenuAnchor(
          childFocusNode: _buttonFocusNode,
          crossAxisUnconstrained: false,
          menuChildren: [
            SizedBox(
              width: 280,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Audio speed',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Slider(
                    min: 0,
                    max: (speeds.length - 1).toDouble(),
                    divisions: speeds.length - 1,
                    value: _speedIndex(widget.manager.speed).toDouble(),
                    label: '${_formatSpeed(widget.manager.speed)}x',
                    onChanged: (index) {
                      widget.manager.setSpeed(speeds[index.round()]);
                    },
                  ),
                ],
              ),
            ),
            // ),
          ],
          builder: (_, MenuController controller, Widget? child) {
            return IconButton(
              tooltip: 'Adjust speed',
              focusNode: _buttonFocusNode,
              onPressed: () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
              icon: Text(
                '${_formatSpeed(widget.manager.speed)}x',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            );
          },
        ),
      ),
    );
  }
}

String _formatSpeed(double speed) {
  return speed == speed.roundToDouble()
      ? speed.toStringAsFixed(0)
      : speed.toString();
}
