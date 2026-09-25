import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../common/epub/models/epub_source.dart';
import '../../../../common/epub/models/loaded_epub.dart';
import '../../../../common/epub/repositories/epub_repo.dart';
import '../../../../common/utils/either.dart';
import '../../domain/file_selection_profile.dart';
import '../../domain/match_result.dart';
import '../../domain/search_options.dart';
import '../../data/search_replace_repo.dart';

part 'search_replace_state.dart';
part 'search_replace_cubit.freezed.dart';

class SearchReplaceCubit extends Cubit<SearchReplaceState> {
  SearchReplaceCubit(this._epubRepo, this._searchReplaceRepo) : super(const SearchReplaceState.idle());

  final EpubRepository _epubRepo;
  final SearchReplaceRepository _searchReplaceRepo;

  _Ready? get _ready => state is _Ready ? state as _Ready : null;

  // ── Carga ──────────────────────────────────────────────────────────────────

  Future<void> loadSources(EpubSource source) async {
    final paths = _resolvePaths(source);
    if (paths.isEmpty) return;

    final label = paths.length == 1 ? paths.first.split(RegExp(r'[/\\]')).last : '${paths.length} EPUBs';
    emit(SearchReplaceState.loading('Cargando $label…'));

    final epubs = await _loadPaths(paths);
    if (epubs.isEmpty) {
      emit(const SearchReplaceState.failure('No se encontraron EPUBs válidos.'));
      return;
    }
    emit(SearchReplaceState.ready(epubs: epubs));
  }

  Future<void> addSources(EpubSource source) async {
    final ready = _ready;
    if (ready == null) return;

    final paths = _resolvePaths(source);
    final newPaths = paths.where((p) => !ready.epubs.any((e) => e.path == p)).toList();
    if (newPaths.isEmpty) return;

    emit(ready.copyWith(isProcessing: true));
    final newEpubs = await _loadPaths(newPaths);
    emit(ready.copyWith(epubs: [...ready.epubs, ...newEpubs], isProcessing: false));
  }

  void removeEpub(String path) {
    final ready = _ready;
    if (ready == null) return;

    _epubRepo.unloadEpub(path);
    final newEpubs = ready.epubs.where((e) => e.path != path).toList();
    if (newEpubs.isEmpty) {
      emit(const SearchReplaceState.idle());
      return;
    }

    int? newFocus = ready.focusedEpubIndex;
    if (newFocus != null) {
      final removedIdx = ready.epubs.indexWhere((e) => e.path == path);
      if (removedIdx == newFocus) {
        newFocus = null;
      } else if (removedIdx < newFocus) {
        newFocus = newFocus - 1;
      }
    }

    emit(ready.copyWith(epubs: newEpubs, focusedEpubIndex: newFocus));
  }

  void resetToIdle() {
    for (final path in _epubRepo.loadedPaths) {
      _epubRepo.unloadEpub(path);
    }
    emit(const SearchReplaceState.idle());
  }

  // ── Navegación ─────────────────────────────────────────────────────────────

  void focusEpub(int index) {
    final ready = _ready;
    if (ready == null || index >= ready.epubs.length) return;
    emit(
      ready.copyWith(
        focusedEpubIndex: index,
        searchPattern: '',
        replacePattern: '',
        patternError: null,
        results: [],
        totalMatches: 0,
        lastReplacedCount: null,
        errorMessage: null,
      ),
    );
  }

  void unfocusEpub() {
    final ready = _ready;
    if (ready == null) return;
    emit(
      ready.copyWith(
        focusedEpubIndex: null,
        searchPattern: '',
        replacePattern: '',
        patternError: null,
        results: [],
        totalMatches: 0,
        lastReplacedCount: null,
        errorMessage: null,
      ),
    );
  }

  // ── Selección de archivos ──────────────────────────────────────────────────

  // ids semántica:
  //   null  → reset a implícito (no guardar nada en memoria)
  //   []    → explícitamente inactivo (ningún archivo)
  //   [...] → subconjunto explícito
  //
  // Optimización: si el resultado explicito contiene TODOS los archivos del epub,
  // se colapsa automáticamente a null para no ocupar memoria innecesaria.
  void changeEpubFileSelection(int epubIndex, List<String>? ids) {
    final ready = _ready;
    if (ready == null || epubIndex >= ready.epubs.length) return;

    final epub = ready.epubs[epubIndex];

    // Colapso a null si el usuario acaba de seleccionar todos los archivos.
    final resolved = ids != null && ids.length == epub.totalFileCount ? null : ids;

    final updated = [...ready.epubs]..[epubIndex] = epub.copyWith(selectedFileIds: resolved);
    emit(ready.copyWith(epubs: updated));
  }

  // Perfil 'all'  → null (implícito, sin guardar lista en memoria).
  // Perfil 'none' → [] (explícitamente inactivo).
  // Otros         → IDs filtrados por tipo de medio.
  // epubIndex null = aplica a todos los EPUBs de la sesión.
  void applySelectionProfile(FileSelectionProfile profile, {int? epubIndex}) {
    final ready = _ready;
    if (ready == null) return;

    List<String>? idsFor(LoadedEpub e) => switch (profile) {
      FileSelectionProfile.all => null,
      FileSelectionProfile.none => const [],
      _ => profile.matchingIds(e.textFiles),
    };

    final updater = (LoadedEpub e) => e.copyWith(selectedFileIds: idsFor(e));

    final updated = epubIndex != null ? ([...ready.epubs]..[epubIndex] = updater(ready.epubs[epubIndex])) : ready.epubs.map(updater).toList();

    emit(ready.copyWith(epubs: updated));
  }

  // ── Patrón / opciones ─────────────────────────────────────────────────────

  void changePattern(String pattern) {
    final ready = _ready;
    if (ready == null) return;
    emit(
      ready.copyWith(
        searchPattern: pattern,
        patternError: _validatePattern(pattern, ready.isRegexMode),
        lastReplacedCount: null,
        errorMessage: null,
      ),
    );
  }

  void changeReplacement(String replacement) {
    final ready = _ready;
    if (ready == null) return;
    emit(
      ready.copyWith(
        replacePattern: replacement,
        lastReplacedCount: null,
        errorMessage: null,
      ),
    );
  }

  void toggleRegexMode() {
    final ready = _ready;
    if (ready == null) return;
    final newMode = !ready.isRegexMode;
    emit(
      ready.copyWith(
        isRegexMode: newMode,
        patternError: _validatePattern(ready.searchPattern, newMode),
        lastReplacedCount: null,
      ),
    );
  }

  void toggleCaseSensitivity() {
    final ready = _ready;
    if (ready == null) return;
    emit(ready.copyWith(isCaseSensitive: !ready.isCaseSensitive, lastReplacedCount: null));
  }

  // ── Búsqueda / reemplazo ───────────────────────────────────────────────────

  Future<void> executeSearch() async {
    final ready = _ready;
    if (ready == null || ready.patternError != null) return;

    emit(ready.copyWith(isProcessing: true, errorMessage: null));

    final result = await _searchReplaceRepo.search(_buildOptions(ready), _targetEpubs(ready));
    result.fold(
      (f) => emit(ready.copyWith(isProcessing: false, errorMessage: f.toString())),
      (results) {
        final total = results.fold<int>(0, (s, r) => s + r.totalMatches);
        emit(ready.copyWith(isProcessing: false, results: results, totalMatches: total));
      },
    );
  }

  Future<void> replaceAll() async {
    final ready = _ready;
    if (ready == null || ready.patternError != null) return;

    emit(ready.copyWith(isProcessing: true, errorMessage: null));

    final targets = _targetEpubs(ready);
    final result = await _searchReplaceRepo.replaceAll(
      _buildOptions(ready),
      ready.replacePattern,
      targets,
    );

    await result.fold(
      (f) async => emit(ready.copyWith(isProcessing: false, errorMessage: f.toString())),
      (count) async {
        final searchResult = await _searchReplaceRepo.search(_buildOptions(ready), targets);
        searchResult.fold(
          (f) => emit(ready.copyWith(isProcessing: false, errorMessage: f.toString())),
          (results) {
            final total = results.fold<int>(0, (s, r) => s + r.totalMatches);
            emit(
              ready.copyWith(
                isProcessing: false,
                lastReplacedCount: count,
                results: results,
                totalMatches: total,
                isSaved: false,
              ),
            );
          },
        );
      },
    );
  }

  Future<void> replaceSingle(FileSearchResult fileResult, MatchResult match) async {
    final ready = _ready;
    if (ready == null || ready.patternError != null) return;

    emit(ready.copyWith(isProcessing: true, errorMessage: null));

    final result = await _searchReplaceRepo.replaceSingle(
      _buildOptions(ready),
      fileResult,
      match,
      ready.replacePattern,
    );

    await result.fold(
      (f) async => emit(ready.copyWith(isProcessing: false, errorMessage: f.toString())),
      (replaced) async {
        if (!replaced) {
          emit(
            ready.copyWith(
              isProcessing: false,
              errorMessage: 'La coincidencia ya no existe (el contenido ha cambiado).',
            ),
          );
          return;
        }
        final targets = _targetEpubs(ready);
        final searchResult = await _searchReplaceRepo.search(_buildOptions(ready), targets);
        searchResult.fold(
          (f) => emit(ready.copyWith(isProcessing: false, errorMessage: f.toString())),
          (results) {
            final total = results.fold<int>(0, (s, r) => s + r.totalMatches);
            emit(
              ready.copyWith(
                isProcessing: false,
                results: results,
                totalMatches: total,
                isSaved: false,
              ),
            );
          },
        );
      },
    );
  }

  // ── Guardado ───────────────────────────────────────────────────────────────

  Future<void> save({int? epubIndex}) async {
    final ready = _ready;
    if (ready == null) return;

    emit(ready.copyWith(isProcessing: true, isSaved: false));

    final toSave = epubIndex != null ? [ready.epubs[epubIndex].path] : ready.epubs.map((e) => e.path).toList();

    String? lastError;
    for (final path in toSave) {
      final r = await _epubRepo.saveEpub(path);
      r.fold((f) => lastError = f.toString(), (_) {});
    }

    emit(
      ready.copyWith(
        isProcessing: false,
        isSaved: lastError == null,
        errorMessage: lastError,
      ),
    );
  }

  Future<Uint8List?> encodeForExport(String epubPath) async {
    final ready = _ready;
    if (ready == null) return null;
    final result = await _epubRepo.encodeEpub(epubPath);
    return result.fold(
      (f) {
        emit(ready.copyWith(errorMessage: f.toString()));
        return null;
      },
      (bytes) => bytes,
    );
  }

  void markSaved() {
    final ready = _ready;
    if (ready == null) return;
    emit(ready.copyWith(isProcessing: false, isSaved: true));
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  List<LoadedEpub> _targetEpubs(_Ready ready) => ready.focusedEpubIndex != null ? [ready.epubs[ready.focusedEpubIndex!]] : ready.epubs;

  List<String> _resolvePaths(EpubSource source) => source.when(
    files: (paths) => paths,
    directory: (path, recursive) => _epubRepo.discoverEpubs(path, recursive: recursive).getOrElse((_) => []),
  );

  Future<List<LoadedEpub>> _loadPaths(List<String> paths) async {
    final epubs = <LoadedEpub>[];
    for (final path in paths) {
      final result = await _epubRepo.loadEpub(path);
      result.fold(
        (_) {},
        (textFiles) => epubs.add(LoadedEpub(path: path, textFiles: textFiles)),
      );
    }
    return epubs;
  }

  SearchOptions _buildOptions(_Ready ready) => SearchOptions(
    pattern: ready.searchPattern,
    isRegex: ready.isRegexMode,
    isCaseSensitive: ready.isCaseSensitive,
    selectedFileIds: const [],
  );

  String? _validatePattern(String pattern, bool isRegex) {
    if (pattern.isEmpty || !isRegex) return null;
    try {
      RegExp(pattern);
      return null;
    } on FormatException catch (e) {
      return e.message;
    }
  }
}
