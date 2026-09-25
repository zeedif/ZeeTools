import '../../../../common/epub/models/epub_manifest_item.dart';

// 'all'  → reset a modo implícito (todos los archivos de todos los epubs activos).
// 'none' → modo explícito con esta selección vacía (epub inactivo en la sesión).
// El cubit distingue ambos casos vía isExplicitSelectionMode.
enum FileSelectionProfile { all, none, xhtml, css, opf, js }

extension FileSelectionProfileX on FileSelectionProfile {
  String get label => switch (this) {
    FileSelectionProfile.all => 'Todo',
    FileSelectionProfile.none => 'Ninguno',
    FileSelectionProfile.xhtml => 'XHTML',
    FileSelectionProfile.css => 'CSS',
    FileSelectionProfile.opf => 'OPF',
    FileSelectionProfile.js => 'JS',
  };

  List<String> matchingIds(List<EpubManifestItem> files) => switch (this) {
    FileSelectionProfile.all => const [],
    FileSelectionProfile.none => const [],
    FileSelectionProfile.xhtml => files.where((f) => f.mediaType.contains('html')).map((f) => f.id).toList(),
    FileSelectionProfile.css => files.where((f) => f.mediaType.contains('css')).map((f) => f.id).toList(),
    FileSelectionProfile.opf => files.where((f) => f.mediaType.contains('package') || f.mediaType.contains('opf')).map((f) => f.id).toList(),
    FileSelectionProfile.js => files.where((f) => f.mediaType.contains('script') || f.mediaType.contains('javascript')).map((f) => f.id).toList(),
  };
}
