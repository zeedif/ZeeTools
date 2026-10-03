import 'package:flutter/material.dart';

import '/common/epub/models/epub_manifest_item.dart';
import '/common/epub/models/loaded_epub.dart';
import '../../../domain/image_format.dart';
import '../../../domain/image_job.dart';
import '../../../domain/optimization_outcome.dart';
import '../../cubit/image_optimizer_cubit.dart';
import 'epub_image_selector.dart';
import 'job_status.dart';

class EpubResultsWidget extends StatelessWidget {
  const EpubResultsWidget({
    super.key,
    required this.epubs,
    required this.jobs,
    required this.showEpubHeader,
  });

  final List<LoadedEpub> epubs;
  final Map<String, ImageJob> jobs;
  final bool showEpubHeader;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // item null = cabecera del EPUB.
    final rows = <(LoadedEpub, EpubManifestItem?)>[
      for (final epub in epubs)
        if (epub.activeFiles.isNotEmpty) ...[
          if (showEpubHeader) (epub, null),
          for (final item in [...epub.activeFiles]..sort((a, b) => a.href.toLowerCase().compareTo(b.href.toLowerCase()))) (epub, item),
        ],
    ];

    var before = 0;
    var after = 0;
    var count = 0;
    for (final (epub, item) in rows) {
      if (item == null) continue;
      count++;
      if (jobs[ImageOptimizerCubit.epubJobKey(epub.path, item.id)] case DoneJob(outcome: OptimizedOutcome(:final originalSize, :final newSize))) {
        before += originalSize;
        after += newSize;
      }
    }

    if (rows.isEmpty) {
      return Center(
        child: Text('No hay imágenes seleccionadas', style: tt.bodyMedium?.copyWith(color: cs.outline)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: cs.surfaceContainerHighest,
          child: Text(
            [
              '$count imagen${count == 1 ? '' : 'es'} seleccionada${count == 1 ? '' : 's'}',
              if (before > 0) 'optimizadas: ${formatBytes(before)} → ${formatBytes(after)} (${savingsLabel(before, after)})',
            ].join('  ·  '),
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final (epub, item) = rows[index];
              if (item == null) {
                return Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                  child: Text(
                    epub.displayName,
                    style: tt.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.image_outlined, size: 18, color: cs.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Tooltip(
                            message: item.href,
                            waitDuration: const Duration(milliseconds: 400),
                            child: Text(displayFileName(item.href), style: tt.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          Text(
                            [ImageFormat.fromMediaType(item.mediaType)?.label ?? item.mediaType, if (item.properties.contains('cover-image')) 'portada'].join(' · '),
                            style: tt.labelSmall?.copyWith(color: cs.outline),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(child: JobStatus(job: jobs[ImageOptimizerCubit.epubJobKey(epub.path, item.id)])),
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
