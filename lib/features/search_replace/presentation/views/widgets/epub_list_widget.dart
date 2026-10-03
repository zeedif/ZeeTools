import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '/common/epub/models/loaded_epub.dart';
import '/common/theme/app_dimensions.dart';
import '../../../domain/file_selection_profile.dart';
import '../../cubit/search_replace_cubit.dart';
import 'profile_pills_row.dart';

class EpubListWidget extends StatelessWidget {
  const EpubListWidget({
    super.key,
    required this.epubs,
    required this.pillOrder,
    required this.sortAscending,
    required this.cubit,
  });

  final List<LoadedEpub> epubs;
  final List<FileSelectionProfile> pillOrder;
  final bool sortAscending;
  final SearchReplaceCubit cubit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // Resumen global de archivos activos.
    final totalActive = epubs.fold(0, (s, e) => s + e.activeFiles.length);
    final totalFiles = epubs.fold(0, (s, e) => s + e.totalFileCount);
    int byName((int, LoadedEpub) a, (int, LoadedEpub) b) =>
        sortAscending ? a.$2.displayName.compareTo(b.$2.displayName) : b.$2.displayName.compareTo(a.$2.displayName);
    final sortedEpubs = [...epubs.indexed]..sort(byName);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Cabecera con perfiles globales ────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      epubs.isPureImplicit
                          ? 'EPUBs (${epubs.length}) · $totalFiles archivos'
                          : 'EPUBs (${epubs.length}) · $totalActive/$totalFiles activos',
                      style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                  Tooltip(
                    message: sortAscending ? 'Orden alfabético ascendente' : 'Orden alfabético descendente',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.small),
                      onTap: cubit.toggleSortAscending,
                      child: Padding(
                        padding: const EdgeInsets.all(AppPadding.small),
                        child: Icon(sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 16, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ProfilePillsRow(order: pillOrder, isActive: _isGlobalActive, onTap: cubit.applySelectionProfile, onReorder: cubit.reorderPills),
            ],
          ),
        ),

        // ── Tiles de EPUBs ────────────────────────────────────────────────
        Expanded(
          child: ListView.builder(
            itemCount: sortedEpubs.length,
            itemBuilder: (ctx, i) => _EpubTile(
              epub: sortedEpubs[i].$2,
              index: sortedEpubs[i].$1,
              cubit: cubit,
            ),
          ),
        ),
      ],
    );
  }

  bool _isGlobalActive(FileSelectionProfile p) {
    return switch (p) {
      FileSelectionProfile.all => epubs.isPureImplicit,
      FileSelectionProfile.none => epubs.every((e) => e.isExplicitlyInactive),
      _ =>
        !epubs.isPureImplicit &&
            epubs.every((e) {
              if (e.isImplicit) return false;
              final expected = p.matchingIds(e.files);
              final ids = e.selectedFileIds ?? [];
              if (expected.isEmpty && ids.isEmpty) return true;
              return expected.length == ids.length && expected.every((id) => ids.contains(id));
            }),
    };
  }
}

class _EpubTile extends StatelessWidget {
  const _EpubTile({required this.epub, required this.index, required this.cubit});

  final LoadedEpub epub;
  final int index;
  final SearchReplaceCubit cubit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // Estado visual del tile según modo del epub.
    final (countText, countColor) = switch (epub.selectedFileIds) {
      null => ('${epub.totalFileCount} archivos', cs.onSurfaceVariant),
      [] => ('Sin archivos activos', cs.error),
      final ids => ('${ids.length}/${epub.totalFileCount} archivos', cs.primary),
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
                          message: epub.displayName,
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
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SvgPicture.asset(
                              'assets/icons/epub.svg',
                              width: 12,
                              height: 12,
                              colorFilter: ColorFilter.mode(countColor, BlendMode.srcIn),
                            ),
                            const SizedBox(width: 4),
                            Text(countText, style: tt.labelSmall?.copyWith(color: countColor)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 18),
                    tooltip: 'Ver archivos',
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
                    onPressed: () => cubit.removeEpub(epub.path),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withAlpha(80)),
        ],
      ),
    );
  }
}
