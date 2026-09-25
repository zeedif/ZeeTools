import 'dart:math' as math;

import 'package:flutter/material.dart';

class SpeedDialAction {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const SpeedDialAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
}

class SpeedDialFab extends StatefulWidget {
  final List<SpeedDialAction> actions;

  const SpeedDialFab({super.key, required this.actions});

  @override
  State<SpeedDialFab> createState() => _SpeedDialFabState();
}

class _SpeedDialFabState extends State<SpeedDialFab> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_controller.isDismissed) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  Widget _buildAnimatedItem(Widget child, int index, int total) {
    // Items closest to the FAB (highest index) animate first when opening.
    final double start = total > 1 ? (total - 1 - index) / total * 0.4 : 0.0;
    final double end = (start + 0.6).clamp(0.0, 1.0);

    final curve = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, end, curve: Curves.easeOutBack),
    );

    // SizeTransition collapses height to zero when closed so items take no space.
    // bottomRight alignment keeps content right-aligned as height grows.
    return SizeTransition(
      sizeFactor: CurvedAnimation(
        parent: _controller,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      ),
      alignment: Alignment.bottomRight,
      child: FadeTransition(
        opacity: curve,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.7, end: 1.0).animate(curve),
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildActionRow(SpeedDialAction action) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Card(
          elevation: 2,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: InkWell(
            onTap: () {
              _toggle();
              action.onPressed();
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(
                action.label,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Right padding compensates for size difference: (56 - 40) / 2 = 8
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: FloatingActionButton.small(
            heroTag: null,
            onPressed: () {
              _toggle();
              action.onPressed();
            },
            child: Icon(action.icon),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.actions.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // AnimatedBuilder ensures IgnorePointer re-evaluates on every animation tick.
        AnimatedBuilder(
          animation: _controller,
          builder: (_, child) => IgnorePointer(
            ignoring: _controller.isDismissed,
            child: child,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(
              total,
              (i) => _buildAnimatedItem(_buildActionRow(widget.actions[i]), i, total),
            ),
          ),
        ),
        FloatingActionButton(
          onPressed: _toggle,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (_, _) => Transform.rotate(
              angle: _controller.value * (math.pi * 0.75),
              child: const Icon(Icons.add),
            ),
          ),
        ),
      ],
    );
  }
}
