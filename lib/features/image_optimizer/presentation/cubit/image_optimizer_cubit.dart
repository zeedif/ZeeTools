import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../common/epub/models/epub_manifest_item.dart';
import '../../../../common/epub/models/loaded_epub.dart';
import '../../../../common/process/native_tools_repo.dart';
import '../../../../common/utils/either.dart';
import '../../data/image_optimizer_repo.dart';
import '../../data/image_optimizer_settings_repo.dart';
import '../../domain/image_format.dart';
import '../../domain/image_job.dart';
import '../../domain/optimization_options.dart';
import '../../domain/optimization_outcome.dart';
import '../../domain/source_image.dart';

part 'image_optimizer_state.dart';
part 'image_optimizer_cubit.freezed.dart';

// [epubPath] null = imagen suelta.
typedef _Target = ({String key, String? imagePath, String? epubPath, EpubManifestItem? item});

class ImageOptimizerCubit extends Cubit<ImageOptimizerState> {
  ImageOptimizerCubit(this._repo, this._settings) : super(const ImageOptimizerState.idle());

  final ImageOptimizerRepository _repo;
  final ImageOptimizerSettingsRepository _settings;

  static String epubJobKey(String epubPath, String itemId) => '$epubPath::$itemId';

  _Ready? get _ready => state is _Ready ? state as _Ready : null;

  // Aplica [update] sobre el estado actual, no sobre uno capturado antes de un await.
  void _emitReady(_Ready Function(_Ready current) update) {
    final current = _ready;
    if (current != null && !isClosed) emit(update(current));
  }

  void _message(String text, {bool isError = false}) => _emitReady((s) => s.copyWith(message: ImageOptimizerMessage(text, isError: isError)));

  ImageSessionKind? get sessionKind => _ready?.kind;

  bool get recursive => _settings.getRecursive();

  Future<void> setRecursive(bool value) => _settings.saveRecursive(value);

  // ── Carga ──────────────────────────────────────────────────────────────────

  Future<ScanResult> scan(List<String> paths, {bool? recursive}) => _repo.scan(paths, recursive: recursive ?? this.recursive);

  // Con una sesión del mismo tipo añade [paths]; con otra, la reemplaza.
  Future<void> open(ImageSessionKind kind, List<String> paths) async {
    if (paths.isEmpty) return;
    final ready = _ready;
    if (ready != null && ready.kind == kind) return _add(ready, paths);
    if (ready != null) await _closeSession(ready);

    emit(ImageOptimizerState.loading('Cargando ${paths.length == 1 ? paths.first.split(RegExp(r'[/\\]')).last : '${paths.length} ${kind == ImageSessionKind.epubs ? 'EPUBs' : 'imágenes'}'}…'));

    final images = kind == ImageSessionKind.images ? await _describeImages(paths) : <SourceImage>[];
    final epubs = kind == ImageSessionKind.epubs ? await _loadEpubs(paths) : <LoadedEpub>[];
    if (images.isEmpty && epubs.isEmpty) {
      emit(ImageOptimizerState.failure(kind == ImageSessionKind.epubs ? 'No se encontraron EPUBs válidos.' : 'No se pudo leer ninguna imagen.'));
      return;
    }
    emit(
      ImageOptimizerState.ready(
        kind: kind,
        images: images,
        epubs: epubs,
        allowedFormats: _settings.getAllowedFormats(),
        allowConversion: _settings.getAllowConversion(),
        qualityMode: _settings.getQualityMode(),
      ),
    );
  }

  Future<void> _add(_Ready ready, List<String> paths) async {
    if (ready.kind == ImageSessionKind.images) {
      final known = ready.images.map((i) => i.path).toSet();
      final added = await _describeImages(paths.where((p) => !known.contains(p)).toList());
      _emitReady((s) => s.copyWith(images: [...s.images, ...added]));
    } else {
      final known = ready.epubs.map((e) => e.path).toSet();
      final added = await _loadEpubs(paths.where((p) => !known.contains(p)).toList());
      _emitReady((s) => s.copyWith(epubs: [...s.epubs, ...added]));
    }
  }

  Future<List<SourceImage>> _describeImages(List<String> paths) async {
    final images = <SourceImage>[];
    for (final path in paths) {
      try {
        images.add(await _repo.describeImage(path));
      } on FileSystemException {
        continue;
      }
    }
    return images;
  }

  Future<List<LoadedEpub>> _loadEpubs(List<String> paths) async {
    final epubs = <LoadedEpub>[];
    for (final path in paths) {
      (await _repo.loadEpubImages(path)).fold((_) {}, (images) => epubs.add(LoadedEpub(path: path, files: images)));
    }
    return epubs;
  }

  void removeImage(String path) {
    final ready = _ready;
    if (ready == null) return;
    final job = ready.jobs[path];
    if (job is DoneJob && !job.committed) _repo.discardResult(job.outcome);

    final images = ready.images.where((i) => i.path != path).toList();
    if (images.isEmpty) {
      emit(const ImageOptimizerState.idle());
      return;
    }
    emit(ready.copyWith(images: images, jobs: {...ready.jobs}..remove(path)));
  }

  void removeEpub(String path) {
    final ready = _ready;
    if (ready == null) return;

    _repo.unloadEpub(path);
    final epubs = ready.epubs.where((e) => e.path != path).toList();
    if (epubs.isEmpty) {
      emit(const ImageOptimizerState.idle());
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

    emit(
      ready.copyWith(
        epubs: epubs,
        focusedEpubIndex: newFocus,
        jobs: {...ready.jobs}..removeWhere((key, _) => key.startsWith('$path::')),
        dirtyEpubs: {...ready.dirtyEpubs}..remove(path),
      ),
    );
  }

  Future<void> resetToIdle() async {
    final ready = _ready;
    if (ready != null) await _closeSession(ready);
    emit(const ImageOptimizerState.idle());
  }

  Future<void> _closeSession(_Ready ready) async {
    for (final epub in ready.epubs) {
      _repo.unloadEpub(epub.path);
    }
    for (final job in ready.jobs.values) {
      if (job is DoneJob && !job.committed) await _repo.discardResult(job.outcome);
    }
  }

  @override
  Future<void> close() async {
    final ready = _ready;
    if (ready != null) await _closeSession(ready);
    return super.close();
  }

  // ── Navegación y selección (EPUBs) ─────────────────────────────────────────

  void focusEpub(int index) {
    final ready = _ready;
    if (ready == null || index >= ready.epubs.length) return;
    emit(ready.copyWith(focusedEpubIndex: index));
  }

  void unfocusEpub() {
    final ready = _ready;
    if (ready == null) return;
    emit(ready.copyWith(focusedEpubIndex: null));
  }

  // null = todas, [] = ninguna, [...] = subconjunto; si se eligen todas se colapsa a null.
  void changeEpubFileSelection(int epubIndex, List<String>? ids) {
    final ready = _ready;
    if (ready == null || epubIndex >= ready.epubs.length) return;
    final epub = ready.epubs[epubIndex];
    emit(ready.copyWith(epubs: [...ready.epubs]..[epubIndex] = epub.copyWith(selectedFileIds: ids != null && ids.length == epub.totalFileCount ? null : ids)));
  }

  // [format] null con [none] false = todas; [none] = ninguna; si no, solo ese formato.
  // epubIndex null = aplica a todos los EPUBs de la sesión.
  void applySelection({ImageFormat? format, bool none = false, int? epubIndex}) {
    final ready = _ready;
    if (ready == null) return;

    LoadedEpub update(LoadedEpub e) {
      if (none) return e.copyWith(selectedFileIds: const []);
      if (format == null) return e.copyWith(selectedFileIds: null);
      final ids = e.files.where((f) => ImageFormat.fromMediaType(f.mediaType) == format).map((f) => f.id).toList();
      return e.copyWith(selectedFileIds: ids.length == e.totalFileCount ? null : ids);
    }

    emit(ready.copyWith(epubs: epubIndex != null ? ([...ready.epubs]..[epubIndex] = update(ready.epubs[epubIndex])) : ready.epubs.map(update).toList()));
  }

  // ── Opciones ───────────────────────────────────────────────────────────────

  void toggleFormat(ImageFormat format) {
    final ready = _ready;
    if (ready == null || ready.isProcessing) return;
    final current = ready.allowedFormats;
    final contains = current.contains(format);
    final next = ImageFormat.outputs.where((f) => f == format ? !contains : current.contains(f)).toList();
    _settings.saveAllowedFormats(next);
    emit(ready.copyWith(allowedFormats: next, jobs: _withoutPendingResults(ready.jobs)));
  }

  void toggleConversion() {
    final ready = _ready;
    if (ready == null || ready.isProcessing) return;
    final next = !ready.allowConversion;
    _settings.saveAllowConversion(next);
    emit(ready.copyWith(allowConversion: next, jobs: _withoutPendingResults(ready.jobs)));
  }

  void setQualityMode(QualityMode mode) {
    final ready = _ready;
    if (ready == null || ready.isProcessing || ready.qualityMode == mode) return;
    _settings.saveQualityMode(mode);
    emit(ready.copyWith(qualityMode: mode, jobs: _withoutPendingResults(ready.jobs)));
  }

  // Descarta los resultados no aplicados para recalcularlos con las opciones nuevas.
  Map<String, ImageJob> _withoutPendingResults(Map<String, ImageJob> jobs) {
    final kept = <String, ImageJob>{};
    for (final MapEntry(:key, :value) in jobs.entries) {
      if (value is DoneJob && !value.committed) {
        _repo.discardResult(value.outcome);
      } else {
        kept[key] = value;
      }
    }
    return kept;
  }

  // ── Procesamiento ──────────────────────────────────────────────────────────

  Future<void> process() async {
    final ready = _ready;
    if (ready == null || ready.isProcessing) return;

    final targets = _pendingTargets(ready);
    if (targets.isEmpty) {
      _message('No hay imágenes pendientes de optimizar.');
      return;
    }

    emit(ready.copyWith(isProcessing: true, cancelRequested: false, progressDone: 0, progressTotal: targets.length, statusMessage: 'Preparando herramientas…'));

    NativeToolset tools;
    try {
      tools = await _repo.ensureTools(onProgress: (m) => _emitReady((s) => s.copyWith(statusMessage: m)));
    } on NativeToolException catch (e) {
      _emitReady((s) => s.copyWith(isProcessing: false, statusMessage: null, message: ImageOptimizerMessage(e.message, isError: true)));
      return;
    }
    _emitReady((s) => s.copyWith(statusMessage: null));

    await _runPool(
      targets,
      max(1, Platform.numberOfProcessors ~/ 2),
      (target) => _processTarget(target, OptimizationOptions(allowedFormats: ready.allowedFormats.toSet(), allowConversion: ready.allowConversion, qualityMode: ready.qualityMode), tools),
    );

    final done = _ready;
    if (done == null) return;
    var before = 0;
    var after = 0;
    for (final t in targets) {
      if (done.jobs[t.key] case DoneJob(outcome: OptimizedOutcome(:final originalSize, :final newSize))) {
        before += originalSize;
        after += newSize;
      }
    }
    final missing = tools.missing.map((t) => t.command).join(', ');
    _emitReady(
      (s) => s.copyWith(
        isProcessing: false,
        cancelRequested: false,
        message: ImageOptimizerMessage(
          [
            if (before > 0) 'Optimizado: ${formatBytes(before)} → ${formatBytes(after)} (${savingsLabel(before, after)})' else 'Ninguna imagen se pudo reducir',
            if (missing.isNotEmpty) 'Herramientas no disponibles: $missing',
          ].join(' · '),
        ),
      ),
    );
  }

  void cancelProcessing() => _emitReady((s) => s.isProcessing ? s.copyWith(cancelRequested: true) : s);

  Future<void> _processTarget(_Target target, OptimizationOptions options, NativeToolset tools) async {
    final current = _ready;
    if (current == null || current.cancelRequested || !_isPresent(current, target)) return;
    _emitReady((s) => s.copyWith(jobs: {...s.jobs, target.key: const ImageJob.running()}));

    final epubPath = target.epubPath;
    var outcome = epubPath == null ? await _repo.optimizeFile(target.imagePath!, options, tools) : await _repo.optimizeEpubImage(epubPath, target.item!, options, tools);

    // En un EPUB el resultado se aplica al contenedor en memoria.
    var committed = false;
    EpubManifestItem? updatedItem;
    final stillPresent = _ready != null && _isPresent(_ready!, target);
    if (epubPath != null && stillPresent && outcome is OptimizedOutcome) {
      final applied = await _repo.applyToEpub(epubPath, target.item!, outcome);
      await _repo.discardResult(outcome);
      switch (applied) {
        case Right(:final value):
          committed = true;
          updatedItem = value;
        case Left(:final value):
          outcome = OptimizationOutcome.failed(value.toString());
      }
    }

    if (!stillPresent) {
      await _repo.discardResult(outcome);
      return;
    }
    _emitReady((s) {
      var epubs = s.epubs;
      final item = updatedItem;
      if (epubPath != null && item != null) {
        epubs = [
          for (final e in s.epubs) e.path == epubPath ? e.copyWith(files: [for (final f in e.files) f.id == item.id ? item : f]) : e,
        ];
      }
      return s.copyWith(
        epubs: epubs,
        jobs: {
          ...s.jobs,
          target.key: ImageJob.done(outcome, committed: committed),
        },
        dirtyEpubs: committed ? {...s.dirtyEpubs, epubPath!} : s.dirtyEpubs,
        progressDone: s.progressDone + 1,
      );
    });
  }

  bool _isPresent(_Ready s, _Target target) => target.epubPath == null ? s.images.any((i) => i.path == target.imagePath) : s.epubs.any((e) => e.path == target.epubPath);

  // Imágenes sin resultado o fallidas de la sesión o del EPUB enfocado.
  List<_Target> _pendingTargets(_Ready ready) {
    bool pending(String key) => switch (ready.jobs[key]) {
      null => true,
      DoneJob(outcome: FailedOutcome()) => true,
      _ => false,
    };

    if (ready.kind == ImageSessionKind.images) {
      return [
        for (final image in ready.images)
          if (pending(image.path)) (key: image.path, imagePath: image.path, epubPath: null, item: null),
      ];
    }
    final focused = ready.focusedEpubIndex;
    return [
      for (final epub in focused != null ? [ready.epubs[focused]] : ready.epubs)
        for (final item in epub.activeFiles)
          if (pending(epubJobKey(epub.path, item.id))) (key: epubJobKey(epub.path, item.id), imagePath: null, epubPath: epub.path, item: item),
    ];
  }

  static Future<void> _runPool<T>(List<T> items, int concurrency, Future<void> Function(T item) task) async {
    var next = 0;
    Future<void> worker() async {
      while (next < items.length) {
        await task(items[next++]);
      }
    }

    await Future.wait([for (var i = 0; i < min(concurrency, items.length); i++) worker()]);
  }

  // ── Guardado ───────────────────────────────────────────────────────────────

  Future<void> saveImagesInPlace() async {
    final ready = _ready;
    if (ready == null || ready.isProcessing) return;
    emit(ready.copyWith(isProcessing: true));

    var saved = 0;
    String? lastError;
    for (final image in ready.images) {
      final job = ready.jobs[image.path];
      if (job is! DoneJob || job.committed) continue;
      final outcome = job.outcome;
      if (outcome is! OptimizedOutcome) continue;
      try {
        final newPath = await _repo.saveImage(image, outcome);
        await _repo.discardResult(outcome);
        saved++;
        _emitReady(
          (s) => s.copyWith(
            images: [
              for (final i in s.images) i.path == image.path ? i.copyWith(path: newPath, size: outcome.newSize, format: outcome.format) : i,
            ],
            jobs: {...s.jobs}
              ..remove(image.path)
              ..[newPath] = ImageJob.done(outcome, committed: true),
          ),
        );
      } on FileSystemException catch (e) {
        lastError = '${image.displayName}: ${e.message}';
      }
    }

    _emitReady(
      (s) => s.copyWith(
        isProcessing: false,
        message: lastError != null ? ImageOptimizerMessage(lastError, isError: true) : ImageOptimizerMessage('$saved imagen${saved == 1 ? '' : 'es'} guardada${saved == 1 ? '' : 's'}'),
      ),
    );
  }

  // Las imágenes ya óptimas se copian tal cual.
  Future<void> saveImagesToFolder(String directory) async {
    final ready = _ready;
    if (ready == null || ready.isProcessing) return;
    emit(ready.copyWith(isProcessing: true));

    var saved = 0;
    String? lastError;
    for (final image in ready.images) {
      final job = ready.jobs[image.path];
      if (job is! DoneJob) continue;
      try {
        switch (job.outcome) {
          case OptimizedOutcome outcome when !job.committed:
            await _repo.saveImage(image, outcome, targetDir: directory);
          case OptimizedOutcome() || UnchangedOutcome():
            await _repo.copyOriginal(image, directory);
          case SkippedOutcome() || FailedOutcome():
            continue;
        }
        saved++;
      } on FileSystemException catch (e) {
        lastError = '${image.displayName}: ${e.message}';
      }
    }

    _emitReady(
      (s) => s.copyWith(
        isProcessing: false,
        message: lastError != null ? ImageOptimizerMessage(lastError, isError: true) : ImageOptimizerMessage('$saved imagen${saved == 1 ? '' : 'es'} guardada${saved == 1 ? '' : 's'} en la carpeta'),
      ),
    );
  }

  Future<void> saveEpubs({int? epubIndex}) async {
    final ready = _ready;
    if (ready == null || ready.isProcessing) return;
    emit(ready.copyWith(isProcessing: true));

    String? lastError;
    final saved = <String>{};
    for (final path in epubIndex != null ? [ready.epubs[epubIndex].path] : ready.epubs.map((e) => e.path)) {
      (await _repo.saveEpub(path)).fold((f) => lastError = f.toString(), (_) => saved.add(path));
    }

    _emitReady(
      (s) => s.copyWith(
        isProcessing: false,
        dirtyEpubs: s.dirtyEpubs.difference(saved),
        message: lastError != null ? ImageOptimizerMessage(lastError!, isError: true) : const ImageOptimizerMessage('EPUB(s) guardado(s) correctamente'),
      ),
    );
  }

  // Devuelve los bytes en vez de emitirlos.
  Future<Uint8List?> exportEpub(LoadedEpub epub) async {
    return (await _repo.encodeEpub(epub.path)).fold(
      (f) {
        _message(f.toString(), isError: true);
        return null;
      },
      (bytes) => bytes,
    );
  }

  void markExported() => _message('EPUB guardado correctamente');
}

String formatBytes(int bytes) {
  if (bytes >= 1000000) return '${(bytes / 1000000).toStringAsFixed(2)} MB';
  if (bytes >= 1000) return '${(bytes / 1000).toStringAsFixed(1)} KB';
  return '$bytes B';
}

String savingsLabel(int before, int after) {
  if (before == 0) return '0%';
  final pct = (1 - after / before) * 100;
  return pct >= 0 ? '−${pct.toStringAsFixed(1)}%' : '+${(-pct).toStringAsFixed(1)}%';
}
