import 'package:flutter/material.dart';

import '/common/widgets/file_kind_icon.dart';
import '/common/widgets/selection_pill.dart';
import '../../../domain/file_selection_profile.dart';

const _fixedProfiles = [FileSelectionProfile.all, FileSelectionProfile.none];

extension on FileSelectionProfile {
  IconData? get _icon => switch (this) {
    FileSelectionProfile.all => Icons.select_all,
    FileSelectionProfile.none => Icons.deselect,
    _ => null,
  };
}

// Scrollbar visible para cuando no caben todos los pills en el ancho disponible.
// "Todo"/"Ninguno" van fijos primero; el resto de `order` se puede reordenar
// arrastrando (ver _DraggablePill), y el nuevo orden se reporta via onReorder.
class ProfilePillsRow extends StatefulWidget {
  const ProfilePillsRow({
    super.key,
    required this.order,
    required this.isActive,
    required this.onTap,
    required this.onReorder,
  });

  final List<FileSelectionProfile> order;
  final bool Function(FileSelectionProfile profile) isActive;
  final ValueChanged<FileSelectionProfile> onTap;
  final ValueChanged<List<FileSelectionProfile>> onReorder;

  @override
  State<ProfilePillsRow> createState() => _ProfilePillsRowState();
}

class _ProfilePillsRowState extends State<ProfilePillsRow> {
  final _scrollController = ScrollController();
  late List<FileSelectionProfile> _preview = List.of(widget.order);
  FileSelectionProfile? _dragging;

  @override
  void didUpdateWidget(ProfilePillsRow old) {
    super.didUpdateWidget(old);
    if (_dragging == null && old.order != widget.order) _preview = List.of(widget.order);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _moveTo(FileSelectionProfile from, FileSelectionProfile to) {
    final fromIndex = _preview.indexOf(from);
    final toIndex = _preview.indexOf(to);
    if (fromIndex < 0 || toIndex < 0 || fromIndex == toIndex) return;
    setState(() {
      final item = _preview.removeAt(fromIndex);
      _preview.insert(toIndex, item);
    });
  }

  void _commitReorder() {
    if (_dragging == null) return;
    widget.onReorder(_preview);
    setState(() => _dragging = null);
  }

  Widget _pill(FileSelectionProfile p, {Widget? trailing}) {
    final active = widget.isActive(p);
    final kind = p.fileKind;
    return SelectionPill(
      label: p.label,
      icon: p._icon,
      leading: kind == null ? null : FileKindIcon(kind: kind, selected: active, size: 14),
      trailing: trailing,
      selected: active,
      onTap: () => widget.onTap(p),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            for (final p in _fixedProfiles) Padding(padding: const EdgeInsets.only(right: 4), child: _pill(p)),
            for (final p in _preview)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _DraggablePill(
                  key: ValueKey(p),
                  profile: p,
                  currentlyDragging: _dragging,
                  onDragStarted: () => setState(() => _dragging = p),
                  onHover: (from) => _moveTo(from, p),
                  onDrop: _commitReorder,
                  child: _pill(p, trailing: Icon(Icons.drag_indicator, size: 14, color: Theme.of(context).colorScheme.outline)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DraggablePill extends StatelessWidget {
  const _DraggablePill({
    required super.key,
    required this.profile,
    required this.currentlyDragging,
    required this.onDragStarted,
    required this.onHover,
    required this.onDrop,
    required this.child,
  });

  final FileSelectionProfile profile;
  final FileSelectionProfile? currentlyDragging;
  final VoidCallback onDragStarted;
  final ValueChanged<FileSelectionProfile> onHover;
  final VoidCallback onDrop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isThisDragging = currentlyDragging == profile;
    final cs = Theme.of(context).colorScheme;
    // El ripple del InkWell se cancela al pasar a modo arrastre, así que el
    // borde marca por sí solo que el pill sigue sostenido mientras se mueve.
    final feedback = Material(
      type: MaterialType.transparency,
      elevation: 6,
      shadowColor: cs.shadow,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: cs.primary, width: 1.5)),
        child: child,
      ),
    );

    return DragTarget<FileSelectionProfile>(
      onWillAcceptWithDetails: (details) {
        if (details.data != currentlyDragging || details.data == profile) return false;
        onHover(details.data);
        return true;
      },
      onAcceptWithDetails: (_) {},
      builder: (context, candidates, _) {
        final isTarget = candidates.isNotEmpty && !isThisDragging;
        return AnimatedScale(
          scale: isTarget ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
          child: LongPressDraggable<FileSelectionProfile>(
            data: profile,
            delay: const Duration(milliseconds: 250),
            feedback: feedback,
            childWhenDragging: Opacity(opacity: 0.35, child: child),
            onDragStarted: onDragStarted,
            onDragEnd: (_) => onDrop(),
            child: child,
          ),
        );
      },
    );
  }
}
