import 'package:flutter/material.dart';

import '../theme/app_dimensions.dart';

// Chip seleccionable con efecto de pulsación, en densidad completa o `dense`
// (más compacta). `child` hereda el color de [selected] vía [IconTheme]/
// [DefaultTextStyle]; para conservar un color propio, fijarlo explícitamente
// en el hijo.
class SelectionPill extends StatelessWidget {
  const SelectionPill({
    super.key,
    required this.child,
    required this.selected,
    required this.onTap,
    this.color,
    this.dense = false,
    this.tooltip,
  });

  final Widget child;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;
  final bool dense;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = color ?? cs.primary;
    final tint = selected ? accent : cs.onSurfaceVariant;
    final shape = (dense ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.small)) : const StadiumBorder()).copyWith(
      side: BorderSide(color: selected ? accent : cs.outlineVariant),
    );

    final labelStyle = (Theme.of(context).textTheme.labelSmall ?? const TextStyle()).copyWith(fontWeight: FontWeight.w600, color: tint);
    final content = IconTheme.merge(
      data: IconThemeData(size: 14, color: tint),
      child: DefaultTextStyle.merge(style: labelStyle, child: child),
    );

    final pill = Material(
      color: selected ? accent.withValues(alpha: dense ? 0.2 : 0.16) : Colors.transparent,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Padding(
          padding: dense ? const EdgeInsets.symmetric(horizontal: AppPadding.small, vertical: AppPadding.tiny) : const EdgeInsets.symmetric(horizontal: AppPadding.medium, vertical: AppPadding.small),
          child: content,
        ),
      ),
    );

    final margined = dense
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.tiny, vertical: AppSpacing.small),
            child: pill,
          )
        : pill;
    return tooltip == null ? margined : Tooltip(message: tooltip, child: margined);
  }
}
