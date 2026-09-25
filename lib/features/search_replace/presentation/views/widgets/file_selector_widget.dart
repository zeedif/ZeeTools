import 'package:flutter/material.dart';

import '../../../../../common/epub/models/epub_manifest_item.dart';
import '../../../domain/file_selection_profile.dart';

class FileSelectorWidget extends StatelessWidget {
  const FileSelectorWidget({
    super.key,
    required this.files,
    required this.selectedIds,
    required this.onSelectionChanged,
  });

  final List<EpubManifestItem> files;
  // null  → todos implícitos (no hay lista guardada en memoria).
  // []    → explícitamente ninguno (epub inactivo).
  // [...] → subconjunto explícito.
  final List<String>? selectedIds;
  // Callback unificado: null = resetear a implícito, [] = ninguno, [...] = subset.
  final ValueChanged<List<String>?> onSelectionChanged;

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

    return Column(
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
              Text(countLabel, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              // Fila única de perfiles: Todo · Ninguno · XHTML · CSS · OPF · JS
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: FileSelectionProfile.values.map((p) {
                    final active = _isProfileActive(p);
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _onProfileTap(p),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: active ? cs.primaryContainer : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: active ? cs.primary : cs.outlineVariant,
                            ),
                          ),
                          child: Text(
                            p.label,
                            style: tt.labelSmall?.copyWith(
                              color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),

        // ── Lista de archivos ────────────────────────────────────────────────
        Expanded(
          child: ListView.builder(
            itemCount: files.length,
            itemBuilder: (context, index) {
              final item = files[index];
              // En implícito todos aparecen marcados sin guardar la lista.
              final checked = _isImplicit || (selectedIds?.contains(item.id) ?? false);

              return CheckboxListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                controlAffinity: ListTileControlAffinity.leading,
                value: checked,
                onChanged: (_) {
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
                title: Text(
                  item.href.split('/').last,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  item.mediaType.split('/').last,
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
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
