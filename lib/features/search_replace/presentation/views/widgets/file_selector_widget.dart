import 'package:flutter/material.dart';

import '/common/epub/models/epub_manifest_item.dart';
import '/common/epub/utils/epub_file_kind.dart';
import '/common/theme/app_dimensions.dart';
import '/common/widgets/file_kind_icon.dart';
import '/common/widgets/selection_pill.dart';
import '../../../domain/file_selection_profile.dart';
import 'profile_pills_row.dart';

class FileSelectorWidget extends StatelessWidget {
  const FileSelectorWidget({
    super.key,
    required this.files,
    required this.selectedIds,
    required this.onSelectionChanged,
    required this.pillOrder,
    required this.onReorderPills,
    required this.groupByPillOrder,
    required this.onToggleGroupByPillOrder,
    required this.sortAscending,
    required this.onToggleSortAscending,
  });

  final List<EpubManifestItem> files;
  // null  → todos implícitos (no hay lista guardada en memoria).
  // []    → explícitamente ninguno (epub inactivo).
  // [...] → subconjunto explícito.
  final List<String>? selectedIds;
  // Callback unificado: null = resetear a implícito, [] = ninguno, [...] = subset.
  final ValueChanged<List<String>?> onSelectionChanged;
  final List<FileSelectionProfile> pillOrder;
  final ValueChanged<List<FileSelectionProfile>> onReorderPills;
  final bool groupByPillOrder;
  final VoidCallback onToggleGroupByPillOrder;
  final bool sortAscending;
  final VoidCallback onToggleSortAscending;

  bool get _isImplicit => selectedIds == null;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // Cuenta visible siempre — en implícito muestra el total, en explícito la selección.
    final String countLabel = switch (selectedIds) {
      null => 'Archivos · ${files.length}',
      [] => 'Sin archivos activos',
      final ids => '${ids.length}/${files.length} archivos',
    };
    final sortedFiles = files.sortedFor(pillOrder, groupByPillOrder: groupByPillOrder, ascending: sortAscending);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Cabecera ────────────────────────────────────────────────────────
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
                  Expanded(child: Text(countLabel, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant))),
                  SelectionPill(
                    dense: true,
                    label: 'Agrupar',
                    icon: groupByPillOrder ? Icons.layers : Icons.layers_outlined,
                    selected: groupByPillOrder,
                    tooltip: 'Agrupar archivos según el orden de los pills',
                    onTap: onToggleGroupByPillOrder,
                  ),
                  Tooltip(
                    message: sortAscending ? 'Orden alfabético ascendente' : 'Orden alfabético descendente',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.small),
                      onTap: onToggleSortAscending,
                      child: Padding(
                        padding: const EdgeInsets.all(AppPadding.small),
                        child: Icon(sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 16, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ProfilePillsRow(order: pillOrder, isActive: _isProfileActive, onTap: _onProfileTap, onReorder: onReorderPills),
            ],
          ),
        ),

        // ── Lista de archivos ────────────────────────────────────────────────
        Expanded(
          child: ListView.builder(
            itemCount: sortedFiles.length,
            itemBuilder: (context, index) {
              final item = sortedFiles[index];
              // En implícito todos aparecen marcados sin guardar la lista.
              final checked = _isImplicit || (selectedIds?.contains(item.id) ?? false);
              final fileName = item.href.split('/').last;

              return InkWell(
                onTap: () {
                  if (_isImplicit) {
                    // Desmarcar uno en modo implícito → entrar en explícito con
                    // todos los demás. Los otros EPUBs NO se ven afectados.
                    final allExceptThis = files.where((f) => f.id != item.id).map((f) => f.id).toList();
                    onSelectionChanged(allExceptThis);
                    return;
                  }
                  // Modo explícito: toggle normal.
                  final ids = selectedIds!;
                  final next = checked ? ids.where((id) => id != item.id).toList() : [...ids, item.id];
                  // Si el resultado contiene todos los archivos, el cubit lo
                  // colapsará a null automáticamente para ahorrar memoria.
                  onSelectionChanged(next);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      FileKindIcon(kind: EpubFileKind.fromMediaType(item.mediaType), selected: checked),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Tooltip(
                          message: fileName,
                          waitDuration: const Duration(milliseconds: 400),
                          child: Text(
                            fileName,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
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

  void _onProfileTap(FileSelectionProfile p) {
    final result = switch (p) {
      FileSelectionProfile.all => null, // → implícito
      FileSelectionProfile.none => const <String>[], // → ninguno
      _ => p.matchingIds(files), // → subset
    };
    onSelectionChanged(result);
  }

  bool _isProfileActive(FileSelectionProfile p) {
    final ids = selectedIds;
    return switch (p) {
      FileSelectionProfile.all => ids == null,
      FileSelectionProfile.none => ids != null && ids.isEmpty,
      _ => ids != null && _matchesProfile(p, ids),
    };
  }

  bool _matchesProfile(FileSelectionProfile p, List<String> ids) {
    final expected = p.matchingIds(files);
    if (expected.isEmpty) return false;
    return expected.length == ids.length && expected.every((id) => ids.contains(id));
  }
}
