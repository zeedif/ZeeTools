import 'package:flutter/material.dart';

import '../theme/app_dimensions.dart';

// Pill/chip seleccionable con efecto de pulsación al tocar, en dos densidades:
// completa (perfiles, filtros de archivo) y `dense` (chip compacto de
// alternancia, con fuente monoespaciada para etiquetas cortas).
// `icon` es un IconData simple que este widget colorea solo según `selected`;
// `leading` es para cuando quien llama necesita un widget con su propio manejo
// de color/estado (p. ej. un SvgPicture que ya distingue seleccionado/no).
// `color` es el acento de marca del contenido (p. ej. el color de un tipo de archivo);
// si se omite, usa el primario del tema.
class SelectionPill extends StatelessWidget {
  const SelectionPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.leading,
    this.trailing,
    this.color,
    this.dense = false,
    this.tooltip,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? leading;
  final Widget? trailing;
  final Color? color;
  final bool dense;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = color ?? cs.primary;
    final leadingWidget = leading ?? (icon != null ? Icon(icon, size: 14, color: selected ? accent : cs.onSurfaceVariant) : null);
    final shape = (dense ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.small)) : const StadiumBorder()).copyWith(
      side: BorderSide(color: selected ? accent : cs.outlineVariant),
    );
    final labelStyle = dense ? const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, fontFamily: 'monospace') : Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600);

    final pill = Material(
      color: selected ? accent.withValues(alpha: dense ? 0.2 : 0.16) : Colors.transparent,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Padding(
          padding: dense ? const EdgeInsets.symmetric(horizontal: AppPadding.small, vertical: AppPadding.tiny) : const EdgeInsets.symmetric(horizontal: AppPadding.medium, vertical: AppPadding.small),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leadingWidget != null) ...[
                SizedBox(width: 14, height: 14, child: leadingWidget),
                const SizedBox(width: AppSpacing.small),
              ],
              Text(label, style: labelStyle?.copyWith(color: selected ? accent : cs.onSurfaceVariant)),
              if (trailing != null) ...[const SizedBox(width: AppSpacing.small), trailing!],
            ],
          ),
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
