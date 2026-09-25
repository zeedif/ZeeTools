import 'package:flutter/material.dart';

// Fila con un panel izquierdo de ancho ajustable (arrastrando el divisor) y un
// cuerpo que ocupa el resto. El ancho no se persiste entre sesiones.
class ResizableSplitPanel extends StatefulWidget {
  const ResizableSplitPanel({
    super.key,
    required this.panel,
    required this.body,
    this.initialWidth = 220,
    this.minWidth = 160,
    this.maxWidth = 420,
  });

  final Widget panel;
  final Widget body;
  final double initialWidth;
  final double minWidth;
  final double maxWidth;

  @override
  State<ResizableSplitPanel> createState() => _ResizableSplitPanelState();
}

class _ResizableSplitPanelState extends State<ResizableSplitPanel> {
  late double _width = widget.initialWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: _width, child: widget.panel),
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate: (details) {
            setState(() => _width = (_width + details.delta.dx).clamp(widget.minWidth, widget.maxWidth));
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: Container(
              width: 4,
              color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
        ),
        Expanded(child: widget.body),
      ],
    );
  }
}
