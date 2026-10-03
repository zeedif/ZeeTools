import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '/common/epub/models/epub_failure.dart';
import '/common/epub/models/epub_manifest_item.dart';
import '/common/epub/repositories/epub_repo.dart';
import '/common/epub/utils/epub_media_types.dart';
import '/common/process/native_tools_repo.dart';
import '/common/utils/either.dart';
import '../domain/image_format.dart';
import '../domain/optimization_options.dart';
import '../domain/optimization_outcome.dart';
import '../domain/source_image.dart';
import 'image_optimizer_engine.dart';

abstract interface class ImageOptimizerRepository {
  Future<ScanResult> scan(List<String> paths, {required bool recursive});
  Future<SourceImage> describeImage(String path);
  Future<Either<EpubFailure, List<EpubManifestItem>>> loadEpubImages(String epubPath);
  void unloadEpub(String epubPath);
  Future<NativeToolset> ensureTools({void Function(String message)? onProgress});
  Future<OptimizationOutcome> optimizeFile(String path, OptimizationOptions options, NativeToolset tools);
  Future<OptimizationOutcome> optimizeEpubImage(String epubPath, EpubManifestItem item, OptimizationOptions options, NativeToolset tools);
  Future<Either<EpubFailure, EpubManifestItem>> applyToEpub(String epubPath, EpubManifestItem item, OptimizedOutcome outcome);
  // Sin [targetDir] reemplaza el original. Devuelve la ruta escrita.
  Future<String> saveImage(SourceImage image, OptimizedOutcome outcome, {String? targetDir});
  Future<String> copyOriginal(SourceImage image, String targetDir);
  Future<Either<EpubFailure, void>> saveEpub(String epubPath);
  Future<Either<EpubFailure, Uint8List>> encodeEpub(String epubPath);
  Future<void> discardResult(OptimizationOutcome outcome);
}

class ImageOptimizerRepositoryImpl(final EpubRepository _epubRepo, final NativeToolsRepository _toolsRepo, final ImageOptimizerEngine _engine) implements ImageOptimizerRepository {
  late final Directory _resultsDir = Directory.systemTemp.createTempSync('zeetools_optimized_');
  // Serializa las sustituciones por EPUB: cada una reescribe el OPF.
  final Map<String, Future<void>> _epubQueues = {};

  @override
  Future<ScanResult> scan(List<String> paths, {required bool recursive}) async {
    final images = <String>{};
    final epubs = <String>{};

    void classify(String path) {
      final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
      if (ext == 'epub') {
        epubs.add(path);
      } else if (ImageFormat.inputExtensions.contains(ext)) {
        images.add(path);
      }
    }

    for (final path in paths) {
      if (await FileSystemEntity.isDirectory(path)) {
        await for (final entity in Directory(path).list(recursive: recursive, followLinks: false)) {
          if (entity is File) classify(entity.path);
        }
      } else {
        classify(path);
      }
    }
    return ScanResult(images: images.toList(), epubs: epubs.toList());
  }

  @override
  Future<SourceImage> describeImage(String path) async {
    final file = File(path);
    return SourceImage(
      path: path,
      size: await file.length(),
      format: ImageFormat.detect(Uint8List.fromList(await file.openRead(0, 32).fold(<int>[], (acc, chunk) => acc..addAll(chunk)))),
    );
  }

  @override
  Future<Either<EpubFailure, List<EpubManifestItem>>> loadEpubImages(String epubPath) => _epubRepo.loadEpub(epubPath, include: EpubMediaTypes.isRasterImageType);

  @override
  void unloadEpub(String epubPath) => _epubRepo.unloadEpub(epubPath);

  @override
  Future<NativeToolset> ensureTools({void Function(String message)? onProgress}) => _toolsRepo.ensureTools(onProgress: onProgress);

  @override
  Future<OptimizationOutcome> optimizeFile(String path, OptimizationOptions options, NativeToolset tools) async {
    try {
      final bytes = await File(path).readAsBytes();
      return await _engine.optimize(bytes, tools: tools, options: options, outputDir: _resultsDir);
    } on FileSystemException catch (e) {
      return OptimizationOutcome.failed(e.message);
    }
  }

  @override
  Future<OptimizationOutcome> optimizeEpubImage(String epubPath, EpubManifestItem item, OptimizationOptions options, NativeToolset tools) async {
    final read = await _epubRepo.readBinaryFile(epubPath, item.archivePath);
    return read.fold(
      (f) => OptimizationOutcome.failed(f.toString()),
      (bytes) => _engine.optimize(bytes, tools: tools, options: options, outputDir: _resultsDir),
    );
  }

  @override
  Future<Either<EpubFailure, EpubManifestItem>> applyToEpub(String epubPath, EpubManifestItem item, OptimizedOutcome outcome) {
    final result = (_epubQueues[epubPath] ?? Future.value()).then(
      (_) async => _epubRepo.replaceResource(epubPath, item, bytes: await File(outcome.resultPath).readAsBytes(), extension: outcome.format.extension, mediaType: outcome.format.mediaType),
    );
    _epubQueues[epubPath] = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<String> saveImage(SourceImage image, OptimizedOutcome outcome, {String? targetDir}) async {
    final inPlace = targetDir == null;
    final target = _freePath(targetDir ?? p.dirname(image.path), p.basenameWithoutExtension(image.path), outcome.format.extension, allow: inPlace ? image.path : null);
    final temp = '$target.zeetools-tmp';
    await File(outcome.resultPath).copy(temp);
    if (inPlace && !p.equals(target, image.path)) await File(image.path).delete();
    await File(temp).rename(target);
    return target;
  }

  @override
  Future<String> copyOriginal(SourceImage image, String targetDir) async {
    final target = _freePath(targetDir, p.basenameWithoutExtension(image.path), p.extension(image.path).replaceFirst('.', ''));
    await File(image.path).copy(target);
    return target;
  }

  @override
  Future<Either<EpubFailure, void>> saveEpub(String epubPath) async {
    await _epubQueues[epubPath];
    return _epubRepo.saveEpub(epubPath);
  }

  @override
  Future<Either<EpubFailure, Uint8List>> encodeEpub(String epubPath) async {
    await _epubQueues[epubPath];
    return _epubRepo.encodeEpub(epubPath);
  }

  @override
  Future<void> discardResult(OptimizationOutcome outcome) async {
    if (outcome case OptimizedOutcome(:final resultPath)) {
      await File(resultPath).delete().catchError((_) => File(resultPath));
    }
  }

  // stem.ext en [dir], o stem-1.ext, stem-2.ext... si ya existe (salvo que sea [allow]).
  static String _freePath(String dir, String stem, String extension, {String? allow}) {
    for (var n = 0; ; n++) {
      final candidate = p.join(dir, '$stem${n == 0 ? '' : '-$n'}.$extension');
      if ((allow != null && p.equals(candidate, allow)) || !File(candidate).existsSync()) return candidate;
    }
  }
}
