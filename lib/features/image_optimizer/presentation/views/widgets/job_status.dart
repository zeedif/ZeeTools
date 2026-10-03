import 'package:flutter/material.dart';

import '../../../domain/image_job.dart';
import '../../../domain/optimization_outcome.dart';
import '../../cubit/image_optimizer_cubit.dart';

class JobStatus extends StatelessWidget {
  const JobStatus({super.key, required this.job, this.compact = false});

  final ImageJob? job;
  // Solo porcentaje o icono.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final muted = tt.labelSmall?.copyWith(color: cs.outline);

    return switch (job) {
      null => Text('Pendiente', style: muted, maxLines: 1, overflow: TextOverflow.ellipsis),
      RunningJob() => const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
      DoneJob(:final outcome, :final committed) => switch (outcome) {
        OptimizedOutcome(:final sourceFormat, :final originalSize, :final newSize, :final format, :final method, :final score, :final alphaRemoved) => _Optimized(
          sizes: '${formatBytes(originalSize)} → ${formatBytes(newSize)}',
          savings: savingsLabel(originalSize, newSize),
          grew: newSize > originalSize,
          detail: [sourceFormat == format ? format.label : '${sourceFormat.label} → ${format.label}', method, if (alphaRemoved) 'alfa eliminado'].join(' · '),
          tooltip: [method, if (score != null) 'SSIMULACRA2 $score', if (alphaRemoved) 'canal alfa sin uso eliminado', if (committed) 'aplicado'].join('\n'),
          committed: committed,
          compact: compact,
        ),
        UnchangedOutcome() =>
          compact
              ? Tooltip(
                  message: 'Ya es óptima',
                  child: Icon(Icons.check, size: 14, color: cs.outline),
                )
              : Text('Ya es óptima', style: muted),
        SkippedOutcome(:final reason) =>
          compact
              ? Tooltip(
                  message: reason,
                  child: Icon(Icons.block, size: 14, color: cs.outline),
                )
              : Text('Omitida: $reason', style: muted, maxLines: 1, overflow: TextOverflow.ellipsis),
        FailedOutcome(:final message) => Tooltip(
          message: message,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 14, color: cs.error),
              if (!compact) ...[const SizedBox(width: 4), Text('Error', style: tt.labelSmall?.copyWith(color: cs.error))],
            ],
          ),
        ),
      },
    };
  }
}

class _Optimized extends StatelessWidget {
  const _Optimized({
    required this.sizes,
    required this.savings,
    required this.grew,
    required this.detail,
    required this.tooltip,
    required this.committed,
    required this.compact,
  });

  final String sizes;
  final String savings;
  final bool grew;
  final String detail;
  final String tooltip;
  final bool committed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = grew ? cs.error : cs.primary;
    final badge = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (committed) ...[Icon(Icons.check_circle, size: 14, color: color), const SizedBox(width: 4)],
        Text(
          savings,
          style: tt.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: compact
          ? badge
          : Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(sizes, style: tt.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 6),
                    badge,
                  ],
                ),
                Text(
                  detail,
                  style: tt.labelSmall?.copyWith(color: cs.outline),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
    );
  }
}
