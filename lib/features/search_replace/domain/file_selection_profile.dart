import '../../../common/epub/models/epub_manifest_item.dart';
import '../../../common/epub/utils/epub_file_kind.dart';

// 'all'  → reset a modo implícito (todos los archivos de todos los epubs activos).
// 'none' → modo explícito con esta selección vacía (epub inactivo en la sesión).
// El cubit distingue ambos casos vía isExplicitSelectionMode.
enum FileSelectionProfile { all, none, xhtml, css, xml, js }

extension FileSelectionProfileX on FileSelectionProfile {
  String get label => switch (this) {
    FileSelectionProfile.all => 'Todo',
    FileSelectionProfile.none => 'Ninguno',
    FileSelectionProfile.xhtml => 'XHTML',
    FileSelectionProfile.css => 'CSS',
    FileSelectionProfile.xml => 'XML',
    FileSelectionProfile.js => 'JS',
  };

  EpubFileKind? get fileKind => switch (this) {
    FileSelectionProfile.all => null,
    FileSelectionProfile.none => null,
    FileSelectionProfile.xhtml => EpubFileKind.xhtml,
    FileSelectionProfile.css => EpubFileKind.css,
    FileSelectionProfile.xml => EpubFileKind.xml,
    FileSelectionProfile.js => EpubFileKind.javascript,
  };

  List<String> matchingIds(List<EpubManifestItem> files) {
    final kind = fileKind;
    if (kind == null) return const [];
    return files.where((f) => EpubFileKind.fromMediaType(f.mediaType) == kind).map((f) => f.id).toList();
  }
}

extension EpubManifestItemListSort on List<EpubManifestItem> {
  // Sin agrupar, orden alfabético puro. Agrupando, primero por el tipo de
  // archivo según su posición en `pillOrder` (los tipos ausentes van al final)
  // y alfabético dentro de cada grupo — `ascending` aplica en ambos casos.
  List<EpubManifestItem> sortedFor(List<FileSelectionProfile> pillOrder, {required bool groupByPillOrder, required bool ascending}) {
    int byName(EpubManifestItem a, EpubManifestItem b) {
      final cmp = a.href.split('/').last.toLowerCase().compareTo(b.href.split('/').last.toLowerCase());
      return ascending ? cmp : -cmp;
    }

    if (!groupByPillOrder) return [...this]..sort(byName);

    final rank = {for (final (i, p) in pillOrder.indexed) p.fileKind: i};
    return [...this]..sort((a, b) {
      final rankA = rank[EpubFileKind.fromMediaType(a.mediaType)] ?? pillOrder.length;
      final rankB = rank[EpubFileKind.fromMediaType(b.mediaType)] ?? pillOrder.length;
      return rankA != rankB ? rankA.compareTo(rankB) : byName(a, b);
    });
  }
}
