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
import '../../data/search_replace_settings_repo.dart';

part 'search_replace_state.dart';
part 'search_replace_cubit.freezed.dart';

class SearchReplaceCubit extends Cubit<SearchReplaceState> {
  SearchReplaceCubit(this._epubRepo, this._searchReplaceRepo, this._settingsRepo) : super(const SearchReplaceState.idle());

  final EpubRepository _epubRepo;
  final SearchReplaceRepository _searchReplaceRepo;
  final SearchReplaceSettingsRepository _settingsRepo;

  // Guardan la seguridad ante llamadas concurrentes a nivel de cubit — no
  // dependen de que la UI deshabilite un botón vía isProcessing, así que
  // siguen protegiendo aunque algún otro punto de la UI llame al método
  // directamente.
  final _searchRace = _Racer();
  final _replaceGate = _Gate();

  _Ready? get _ready => state is _Ready ? state as _Ready : null;

  // Aplica [update] sobre el estado ready *actual* (no uno capturado antes de
  // un await), para no revertir cambios no relacionados ocurridos mientras la
  // operación estaba en vuelo (p. ej. teclear en el buscador durante un reemplazo).
  void _emitReady(_Ready Function(_Ready current) update) {
    final current = _ready;
    if (current != null) emit(update(current));
  }

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
    emit(
      SearchReplaceState.ready(
        epubs: epubs,
        pillOrder: _settingsRepo.getOrder(),
        groupFilesByPillOrder: _settingsRepo.getGroupFilesByPillOrder(),
        sortAscending: _settingsRepo.getSortAscending(),
        isRegexMode: _settingsRepo.getIsRegexMode(),
        isCaseSensitive: _settingsRepo.getIsCaseSensitive(),
        isWholeWord: _settingsRepo.getIsWholeWord(),
        preserveCase: _settingsRepo.getPreserveCase(),
      ),
    );
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
        hasSearched: false,
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
        hasSearched: false,
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

  void reorderPills(List<FileSelectionProfile> order) {
    final ready = _ready;
    if (ready == null) return;
    emit(ready.copyWith(pillOrder: order));
    _settingsRepo.saveOrder(order);
  }

  void toggleGroupFilesByPillOrder() {
    final ready = _ready;
    if (ready == null) return;
    final next = !ready.groupFilesByPillOrder;
    emit(ready.copyWith(groupFilesByPillOrder: next));
    _settingsRepo.saveGroupFilesByPillOrder(next);
  }

  void toggleSortAscending() {
    final ready = _ready;
    if (ready == null) return;
    final next = !ready.sortAscending;
    emit(ready.copyWith(sortAscending: next));
    _settingsRepo.saveSortAscending(next);
  }

  // ── Patrón / opciones ─────────────────────────────────────────────────────

  void changePattern(String pattern) {
    final ready = _ready;
    if (ready == null) return;
    emit(
      ready.copyWith(
        searchPattern: pattern,
        patternError: _validatePattern(pattern, ready.isRegexMode),
        hasSearched: false,
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
    _settingsRepo.saveIsRegexMode(newMode);
  }

  void toggleCaseSensitivity() {
    final ready = _ready;
    if (ready == null) return;
    final next = !ready.isCaseSensitive;
    emit(ready.copyWith(isCaseSensitive: next, lastReplacedCount: null));
    _settingsRepo.saveIsCaseSensitive(next);
  }

  void toggleWholeWord() {
    final ready = _ready;
    if (ready == null) return;
    final next = !ready.isWholeWord;
    emit(ready.copyWith(isWholeWord: next, lastReplacedCount: null));
    _settingsRepo.saveIsWholeWord(next);
  }

  void togglePreserveCase() {
    final ready = _ready;
    if (ready == null) return;
    final next = !ready.preserveCase;
    emit(ready.copyWith(preserveCase: next, lastReplacedCount: null));
    _settingsRepo.savePreserveCase(next);
  }

  void focusSearchField() {
    final ready = _ready;
    if (ready == null) return;
    emit(ready.copyWith(focusSearchToken: ready.focusSearchToken + 1));
  }

  // ── Búsqueda / reemplazo ───────────────────────────────────────────────────

  // Restartable: si se dispara otra búsqueda antes de que esta termine, su
  // resultado se descarta — solo la más reciente puede llegar a aplicarse.
  Future<void> executeSearch() async {
    final ready = _ready;
    if (ready == null || ready.patternError != null) return;

    final token = _searchRace.start();
    emit(ready.copyWith(isProcessing: true, errorMessage: null));

    final result = await _searchReplaceRepo.search(_buildOptions(ready), _targetEpubs(ready));
    if (!_searchRace.isCurrent(token)) return;

    result.fold(
      (f) => _emitReady((s) => s.copyWith(isProcessing: false, errorMessage: f.toString())),
      (results) {
        final total = results.fold<int>(0, (s, r) => s + r.totalMatches);
        _emitReady(
          (s) => s.copyWith(
            isProcessing: false,
            hasSearched: true,
            results: results,
            totalMatches: total,
          ),
        );
      },
    );
  }

  // Droppable: una segunda llamada mientras esta sigue en vuelo se ignora en
  // silencio — un reemplazo no debe solaparse con otro sobre el mismo contenido.
  Future<void> replaceAll() async {
    final ready = _ready;
    if (ready == null || ready.patternError != null) return;

    await _replaceGate.run(() async {
      emit(ready.copyWith(isProcessing: true, errorMessage: null));

      final targets = _targetEpubs(ready);
      final result = await _searchReplaceRepo.replaceAll(
        _buildOptions(ready),
        ready.replacePattern,
        targets,
        preserveCase: ready.preserveCase,
      );

      await result.fold(
        (f) async => _emitReady((s) => s.copyWith(isProcessing: false, errorMessage: f.toString())),
        (count) async {
          final searchResult = await _searchReplaceRepo.search(_buildOptions(ready), targets);
          searchResult.fold(
            (f) => _emitReady((s) => s.copyWith(isProcessing: false, errorMessage: f.toString())),
            (results) {
              final total = results.fold<int>(0, (s, r) => s + r.totalMatches);
              _emitReady(
                (s) => s.copyWith(
                  isProcessing: false,
                  hasSearched: true,
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
    });
  }

  // Comparte _replaceGate con replaceAll — ambos mutan el mismo contenido.
  Future<void> replaceSingle(FileSearchResult fileResult, MatchResult match) async {
    final ready = _ready;
    if (ready == null || ready.patternError != null) return;

    await _replaceGate.run(() async {
      emit(ready.copyWith(isProcessing: true, errorMessage: null));

      final result = await _searchReplaceRepo.replaceSingle(
        _buildOptions(ready),
        fileResult,
        match,
        ready.replacePattern,
        preserveCase: ready.preserveCase,
      );

      await result.fold(
        (f) async => _emitReady((s) => s.copyWith(isProcessing: false, errorMessage: f.toString())),
        (replaced) async {
          if (!replaced) {
            _emitReady(
              (s) => s.copyWith(
                isProcessing: false,
                errorMessage: 'La coincidencia ya no existe (el contenido ha cambiado).',
              ),
            );
            return;
          }
          final targets = _targetEpubs(ready);
          final searchResult = await _searchReplaceRepo.search(_buildOptions(ready), targets);
          searchResult.fold(
            (f) => _emitReady((s) => s.copyWith(isProcessing: false, errorMessage: f.toString())),
            (results) {
              final total = results.fold<int>(0, (s, r) => s + r.totalMatches);
              _emitReady((s) => s.copyWith(isProcessing: false, results: results, totalMatches: total, isSaved: false));
            },
          );
        },
      );
    });
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

  // Devuelve los bytes directamente a quien llama en vez de emitirlos como
  // estado: el resultado solo le importa a esa llamada puntual, y una vez en
  // el state compartido cualquier otro emit no relacionado (p. ej. teclear en
  // el buscador) lo arrastraría sin cambios vía copyWith y podría reabrir el
  // diálogo de guardado sin que el usuario haya vuelto a pedirlo.
  Future<Uint8List?> exportEpub(LoadedEpub epub) async {
    final ready = _ready;
    if (ready == null) return null;
    emit(ready.copyWith(isProcessing: true));
    final result = await _epubRepo.encodeEpub(epub.path);
    return result.fold(
      (f) {
        emit(ready.copyWith(isProcessing: false, errorMessage: f.toString()));
        return null;
      },
      (bytes) {
        emit(ready.copyWith(isProcessing: false));
        return bytes;
      },
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
    isWholeWord: ready.isWholeWord,
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

// Reproduce, sin depender de Stream/Bloc, cómo bloc_concurrency's restartable()
// invalida el resultado de una ejecución superada: Bloc cancela un Emitter
// asociado a esa ejecución para que sus emit() posteriores no hagan nada;
// aquí basta comparar el token contra el más reciente antes de aplicar el resultado.
class _Racer {
  Object? _current;

  Object start() => _current = Object();

  bool isCurrent(Object token) => identical(token, _current);
}

// Equivalente a bloc_concurrency's droppable(): ignora una llamada mientras
// la anterior sigue en vuelo, en vez de encolarla o solaparla.
class _Gate {
  bool _busy = false;

  Future<void> run(Future<void> Function() operation) async {
    if (_busy) return;
    _busy = true;
    try {
      await operation();
    } finally {
      _busy = false;
    }
  }
}
