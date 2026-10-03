import 'dart:io';

import 'package:flutter/material.dart';

import '../../../domain/image_job.dart';
import '../../../domain/optimization_outcome.dart';
import '../../../domain/source_image.dart';
import '../../cubit/image_optimizer_cubit.dart';
import 'job_status.dart';

class ImageListWidget extends StatelessWidget {
  const ImageListWidget({
    super.key,
    required this.images,
    required this.jobs,
    required this.isProcessing,
    required this.onRemove,
  });

  final List<SourceImage> images;
  final Map<String, ImageJob> jobs;
  final bool isProcessing;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    var before = 0;
    var after = 0;
    for (final image in images) {
      switch (jobs[image.path]) {
        case DoneJob(outcome: OptimizedOutcome(:final originalSize, :final newSize)):
          before += originalSize;
          after += newSize;
        case DoneJob(outcome: UnchangedOutcome(:final size)):
          before += size;
          after += size;
        default:
          break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: cs.surfaceContainerHighest,
          child: Text(
            [
              '${images.length} imagen${images.length == 1 ? '' : 'es'} · ${formatBytes(images.fold(0, (s, i) => s + i.size))}',
              if (before > 0) 'procesadas: ${formatBytes(before)} → ${formatBytes(after)} (${savingsLabel(before, after)})',
            ].join('  ·  '),
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: images.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: cs.outlineVariant.withAlpha(80)),
            itemBuilder: (context, index) {
              final image = images[index];
              final job = jobs[image.path];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.file(
                        File(image.path),
                        width: 40,
                        height: 40,
                        cacheWidth: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 40,
                          height: 40,
                          color: cs.surfaceContainerHighest,
                          child: Icon(Icons.image_outlined, size: 20, color: cs.outline),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Tooltip(
                            message: image.path,
                            waitDuration: const Duration(milliseconds: 400),
                            child: Text(
                              image.displayName,
                              style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text('${image.format?.label ?? 'Formato desconocido'} · ${formatBytes(image.size)}', style: tt.labelSmall?.copyWith(color: cs.outline)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(child: JobStatus(job: job)),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      tooltip: 'Quitar de la lista',
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      color: cs.onSurfaceVariant,
                      onPressed: job is RunningJob || isProcessing ? null : () => onRemove(image.path),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
