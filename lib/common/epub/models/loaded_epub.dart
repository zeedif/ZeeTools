import 'package:freezed_annotation/freezed_annotation.dart';

import 'epub_manifest_item.dart';

part 'loaded_epub.freezed.dart';

// selectedFileIds semántica:
//   null  → modo implícito: todos los archivos activos (sin guardar la lista en memoria)
//   []    → explícitamente ninguno: este epub está inactivo en la sesión
//   [...] → subconjunto explícito: solo esos archivos están activos
//
// Al pasar de implícito a explícito al desmarcar un archivo, se guarda
// "todos menos ese" sin tocar los demás EPUBs de la sesión.
// Cuando la selección manual resulta en todos los archivos, se colapsa
// automáticamente a null para no ocupar memoria innecesaria.
@Freezed(makeCollectionsUnmodifiable: false)
sealed class LoadedEpub with _$LoadedEpub {
  const LoadedEpub._();

  const factory LoadedEpub({
    required String path,
    required List<EpubManifestItem> textFiles,
    List<String>? selectedFileIds, // null = implicit all (default)
  }) = _LoadedEpub;

  String get displayName => path.split(RegExp(r'[/\\]')).last;

  bool get isImplicit => selectedFileIds == null;
  bool get hasExplicitSelection => selectedFileIds != null && selectedFileIds!.isNotEmpty;
  bool get isExplicitlyInactive => selectedFileIds != null && selectedFileIds!.isEmpty;

  int get explicitCount => selectedFileIds?.length ?? 0;
  int get totalFileCount => textFiles.length;

  // Archivos realmente activos para búsqueda/reemplazo.
  List<EpubManifestItem> get activeFiles {
    final ids = selectedFileIds;
    if (ids == null) return textFiles;
    if (ids.isEmpty) return const [];
    return textFiles.where((f) => ids.contains(f.id)).toList();
  }
}

extension LoadedEpubListX on List<LoadedEpub> {
  // true cuando TODOS los EPUBs están en modo implícito (ninguna selección explícita).
  bool get isPureImplicit => every((e) => e.isImplicit);
}
