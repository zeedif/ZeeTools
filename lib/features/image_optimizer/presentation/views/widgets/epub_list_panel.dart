import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '/common/epub/models/loaded_epub.dart';
import '../../../domain/image_format.dart';
import '../../cubit/image_optimizer_cubit.dart';
import 'epub_image_selector.dart';

class EpubListPanel extends StatelessWidget {
  const EpubListPanel({
    super.key,
    required this.epubs,
    required this.dirtyEpubs,
    required this.isProcessing,
    required this.cubit,
  });

  final List<LoadedEpub> epubs;
  final Set<String> dirtyEpubs;
  final bool isProcessing;
  final ImageOptimizerCubit cubit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final totalFiles = epubs.fold(0, (s, e) => s + e.totalFileCount);
    final sorted = [...epubs.indexed]..sort((a, b) => a.$2.displayName.toLowerCase().compareTo(b.$2.displayName.toLowerCase()));

    bool matchesFormat(ImageFormat format) =>
        !epubs.isPureImplicit &&
        epubs.every((e) {
          final expected = e.files.where((f) => ImageFormat.fromMediaType(f.mediaType) == format).map((f) => f.id).toList();
          final ids = e.selectedFileIds ?? e.files.map((f) => f.id).toList();
          return expected.length == ids.length && expected.every(ids.contains);
        });

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
                epubs.isPureImplicit ? 'EPUBs (${epubs.length}) · $totalFiles imágenes' : 'EPUBs (${epubs.length}) · ${epubs.fold(0, (s, e) => s + e.activeFiles.length)}/$totalFiles activas',
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              ImageSelectionPills(
                formats: formatsIn(epubs.expand((e) => e.files)),
                isAll: epubs.isPureImplicit,
                isNone: epubs.every((e) => e.isExplicitlyInactive),
                isFormat: matchesFormat,
                onAll: () => cubit.applySelection(),
                onNone: () => cubit.applySelection(none: true),
                onFormat: (format) => cubit.applySelection(format: format),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: sorted.length,
            itemBuilder: (context, i) {
              final (index, epub) = sorted[i];
              final (countText, countColor) = switch (epub.selectedFileIds) {
                _ when epub.totalFileCount == 0 => ('Sin imágenes', cs.outline),
                null => ('${epub.totalFileCount} imágenes', cs.onSurfaceVariant),
                [] => ('Sin imágenes activas', cs.error),
                final ids => ('${ids.length}/${epub.totalFileCount} imágenes', cs.primary),
              };

              return Opacity(
                opacity: epub.isExplicitlyInactive ? 0.45 : 1.0,
                child: Column(
                  children: [
                    InkWell(
                      onTap: () => cubit.focusEpub(index),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Tooltip(
                                    message: epub.path,
                                    waitDuration: const Duration(milliseconds: 400),
                                    child: Text(
                                      epub.displayName,
                                      style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      SvgPicture.asset('assets/icons/epub.svg', width: 12, height: 12, colorFilter: ColorFilter.mode(countColor, BlendMode.srcIn)),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          countText,
                                          style: tt.labelSmall?.copyWith(color: countColor),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (dirtyEpubs.contains(epub.path)) ...[
                                        const SizedBox(width: 6),
                                        Tooltip(
                                          message: 'Cambios sin guardar',
                                          child: Icon(Icons.circle, size: 8, color: cs.tertiary),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.chevron_right, size: 18),
                              tooltip: 'Elegir imágenes',
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(),
                              onPressed: () => cubit.focusEpub(index),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              tooltip: 'Quitar',
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(),
                              color: cs.onSurfaceVariant,
                              onPressed: isProcessing ? null : () => cubit.removeEpub(epub.path),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Divider(height: 1, color: cs.outlineVariant.withAlpha(80)),
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
