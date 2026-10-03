import 'package:flutter/material.dart';

import '/common/epub/models/epub_manifest_item.dart';
import '/common/widgets/selection_pill.dart';
import '../../../domain/image_format.dart';
import '../../../domain/image_job.dart';
import '../../cubit/image_optimizer_cubit.dart';
import 'job_status.dart';

class ImageSelectionPills extends StatelessWidget {
  const ImageSelectionPills({
    super.key,
    required this.formats,
    required this.isAll,
    required this.isNone,
    required this.isFormat,
    required this.onAll,
    required this.onNone,
    required this.onFormat,
  });

  final List<ImageFormat> formats;
  final bool isAll;
  final bool isNone;
  final bool Function(ImageFormat format) isFormat;
  final VoidCallback onAll;
  final VoidCallback onNone;
  final ValueChanged<ImageFormat> onFormat;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        SelectionPill(
          selected: isAll,
          onTap: onAll,
          child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.select_all), SizedBox(width: 4), Text('Todo')]),
        ),
        SelectionPill(
          selected: isNone,
          onTap: onNone,
          child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.deselect), SizedBox(width: 4), Text('Ninguno')]),
        ),
        for (final format in formats) SelectionPill(selected: isFormat(format), onTap: () => onFormat(format), child: Text(format.label)),
      ],
    );
  }
}

String displayFileName(String href) {
  final segment = href.split('/').last;
  try {
    return Uri.decodeComponent(segment);
  } on ArgumentError {
    return segment;
  }
}

List<ImageFormat> formatsIn(Iterable<EpubManifestItem> files) {
  final present = files.map((f) => ImageFormat.fromMediaType(f.mediaType)).toSet();
  return ImageFormat.values.where(present.contains).toList();
}

class EpubImageSelector extends StatelessWidget {
  const EpubImageSelector({
    super.key,
    required this.epubPath,
    required this.files,
    required this.selectedIds,
    required this.jobs,
    required this.onSelectionChanged,
  });

  final String epubPath;
  final List<EpubManifestItem> files;
  // null = todas, [] = ninguna, [...] = subconjunto.
  final List<String>? selectedIds;
  final Map<String, ImageJob> jobs;
  final ValueChanged<List<String>?> onSelectionChanged;

  bool get _isImplicit => selectedIds == null;

  List<String> _idsOf(ImageFormat format) => files.where((f) => ImageFormat.fromMediaType(f.mediaType) == format).map((f) => f.id).toList();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final sorted = [...files]..sort((a, b) => a.href.toLowerCase().compareTo(b.href.toLowerCase()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                switch (selectedIds) {
                  null => 'Imágenes · ${files.length}',
                  [] => 'Sin imágenes activas',
                  final ids => '${ids.length}/${files.length} imágenes',
                },
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              ImageSelectionPills(
                formats: formatsIn(files),
                isAll: selectedIds == null,
                isNone: selectedIds != null && selectedIds!.isEmpty,
                isFormat: (format) {
                  final ids = selectedIds;
                  final expected = _idsOf(format);
                  return ids != null && ids.isNotEmpty && expected.length == ids.length && expected.every(ids.contains);
                },
                onAll: () => onSelectionChanged(null),
                onNone: () => onSelectionChanged(const []),
                onFormat: (format) => onSelectionChanged(_idsOf(format)),
              ),
            ],
          ),
        ),
        Expanded(
          child: files.isEmpty
              ? Center(
                  child: Text('Este EPUB no tiene imágenes ráster', style: tt.bodySmall?.copyWith(color: cs.outline)),
                )
              : ListView.builder(
                  itemCount: sorted.length,
                  itemBuilder: (context, index) {
                    final item = sorted[index];
                    final checked = _isImplicit || (selectedIds?.contains(item.id) ?? false);
                    return InkWell(
                      onTap: () {
                        if (_isImplicit) {
                          onSelectionChanged(files.where((f) => f.id != item.id).map((f) => f.id).toList());
                          return;
                        }
                        final ids = selectedIds!;
                        onSelectionChanged(checked ? ids.where((id) => id != item.id).toList() : [...ids, item.id]);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: Row(
                          children: [
                            Icon(checked ? Icons.image : Icons.image_outlined, size: 18, color: checked ? cs.primary : cs.outline),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Tooltip(
                                message: item.href,
                                waitDuration: const Duration(milliseconds: 400),
                                child: Text(displayFileName(item.href), style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                            ),
                            const SizedBox(width: 6),
                            JobStatus(job: jobs[ImageOptimizerCubit.epubJobKey(epubPath, item.id)], compact: true),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
