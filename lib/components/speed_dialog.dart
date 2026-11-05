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

  @override
  void dispose() {
    _buttonFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double currentSpeed = widget.manager.speed;
    return AnimatedBuilder(
      animation: widget.manager,
      builder: (context, _) => SizedBox(
        width: 60,
        height: 48,
        child: MenuAnchor(
          childFocusNode: _buttonFocusNode,
          crossAxisUnconstrained: false,
          menuChildren: [
            for (final speed in speeds)
              MenuItemButton(
                onPressed: () {
                  widget.manager.setSpeed(speed);
                  _buttonFocusNode.requestFocus();
                },
                child: Text(
                  _formatSpeed(speed),
                  style: speed == currentSpeed
                      ? const TextStyle(fontWeight: FontWeight.w800)
                      : const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
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
