import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '/common/process/native_tool.dart';
import '/common/process/native_tools_repo.dart';
import '../domain/image_format.dart';
import '../domain/optimization_options.dart';
import '../domain/optimization_outcome.dart';
import 'image_analysis.dart';

// Elige el candidato más ligero entre los formatos de destino de cada imagen;
// el original siempre compite.
class ImageOptimizerEngine {
  ImageOptimizerEngine({this.threads = 2});

  // Hilos por codificador.
  final int threads;

  static final _jpegliDistances = [for (var i = 1; i <= 30; i++) i / 10];
  static final _jxlDistances = [for (var i = 1; i <= 30; i++) i / 10];
  static final _mozjpegQualities = [for (var q = 100; q >= 60; q--) q];
  static final _webpQualities = [for (var q = 100; q >= 50; q--) q];
  static final _avifQualities = [for (var q = 99; q >= 30; q--) q];
  static const _nearLosslessLevels = [80, 60, 40, 20, 0];

  // Deja el archivo ganador en [outputDir].
  Future<OptimizationOutcome> optimize(
    Uint8List bytes, {
    required NativeToolset tools,
    required OptimizationOptions options,
    required Directory outputDir,
  }) async {
    final source = ImageFormat.detect(bytes);
    if (source == null) return const OptimizationOutcome.skipped('Formato no reconocido');
    if (isAnimatedContainer(source, bytes)) return const OptimizationOutcome.skipped('Imagen animada');

    final work = await Directory.systemTemp.createTemp('zeetools_img_');
    try {
      final src = File(p.join(work.path, 'src.${source.extension}'));
      await src.writeAsBytes(bytes);

      var decodable = bytes;
      if (source == ImageFormat.avif || source == ImageFormat.jxl) {
        final decoded = File(p.join(work.path, 'src_decoded.png'));
        await tools.run(source == ImageFormat.avif ? NativeTool.avifdec : NativeTool.djxl, [src.path, decoded.path]);
        decodable = await decoded.readAsBytes();
      }

      final analysis = await Isolate.run(() => analyzeImage(decodable));
      if (analysis.animated) return const OptimizationOutcome.skipped('Imagen animada');

      final allowed = {
        if (source.isOutput) source,
        if (options.allowConversion) ...options.allowedFormats,
      };
      if (analysis.hasAlpha) allowed.removeWhere((f) => !f.supportsAlpha);
      if (allowed.isEmpty) {
        return OptimizationOutcome.skipped(
          !options.allowConversion ? 'Sin conversión de formato no hay forma de optimizar ${source.label}' : 'Tiene transparencia y ningún formato de destino la admite',
        );
      }

      final ref = File(p.join(work.path, 'ref.png'));
      await ref.writeAsBytes(analysis.referencePng!);

      final search = _CandidateSearch(tools, work, ref, options.threshold);
      if (allowed.contains(source)) {
        search.candidates.add(_Candidate(src, source, 'original', size: bytes.length));
      }

      final keepIcc = analysis.keepsIcc;
      if (source == ImageFormat.jpeg) {
        if (allowed.contains(ImageFormat.jpeg) && tools.has(NativeTool.jpegtran)) {
          // Con orientación EXIF se copia el EXIF para que la imagen no aparezca girada.
          await search.lossless(ImageFormat.jpeg, 'mozjpeg jpegtran', (out) => tools.run(NativeTool.jpegtran, ['-copy', analysis.orientationBaked ? 'all' : (keepIcc ? 'icc' : 'none'), '-optimize', '-progressive', '-outfile', out.path, src.path]));
        }
        if (allowed.contains(ImageFormat.jxl) && tools.has(NativeTool.cjxl)) {
          await search.lossless(ImageFormat.jxl, 'JPEG XL (recompresión reversible del JPEG)', (out) => tools.run(NativeTool.cjxl, [src.path, out.path, '--lossless_jpeg=1', '-e', '7', '--num_threads=$threads', '--quiet']));
        }
      }

      final metadata = keepIcc ? 'icc' : 'none';
      final avifMetadata = ['--ignore-exif', '--ignore-xmp', if (!keepIcc) '--ignore-icc'];
      final losslessSource = isLosslessEncoding(source, bytes);
      if (losslessSource || search.candidates.isEmpty) {
        if (allowed.contains(ImageFormat.png) && tools.has(NativeTool.oxipng)) {
          await search.lossless(ImageFormat.png, 'oxipng', (out) => tools.run(NativeTool.oxipng, ['-q', '-o', '4', '--strip', keepIcc ? 'safe' : 'all', '--alpha', '-t', '$threads', '--out', out.path, ref.path]));
        }
        if (allowed.contains(ImageFormat.webp) && tools.has(NativeTool.cwebp) && _fitsWebp(analysis)) {
          await search.lossless(ImageFormat.webp, 'WebP sin pérdida', (out) => tools.run(NativeTool.cwebp, ['-quiet', '-lossless', '-z', '6', '-metadata', metadata, ref.path, '-o', out.path]));
        }
        if (allowed.contains(ImageFormat.jxl) && tools.has(NativeTool.cjxl)) {
          await search.lossless(ImageFormat.jxl, 'JPEG XL sin pérdida', (out) => tools.run(NativeTool.cjxl, [ref.path, out.path, '-d', '0', '-e', '7', '--num_threads=$threads', '--quiet']));
        }
        if (allowed.contains(ImageFormat.avif) && tools.has(NativeTool.avifenc)) {
          await search.lossless(ImageFormat.avif, 'AVIF sin pérdida', (out) => tools.run(NativeTool.avifenc, ['-l', '-s', '6', '-j', '$threads', ...avifMetadata, ref.path, out.path]));
        }
      }

      if (options.qualityMode == QualityMode.visuallyLossless && tools.has(NativeTool.ssimulacra2)) {
        if (allowed.contains(ImageFormat.jxl) && tools.has(NativeTool.cjxl)) {
          await search.lossy(ImageFormat.jxl, _jxlDistances, (d) => 'JPEG XL d$d', (d, out) => tools.run(NativeTool.cjxl, [ref.path, out.path, '-d', '$d', '-e', '7', '--num_threads=$threads', '--quiet']));
        }
        if (allowed.contains(ImageFormat.avif) && tools.has(NativeTool.avifenc) && tools.has(NativeTool.avifdec)) {
          await search.lossy(ImageFormat.avif, _avifQualities, (q) => 'AVIF q$q', (q, out) => tools.run(NativeTool.avifenc, ['-q', '$q', '-s', '6', '-j', '$threads', ...avifMetadata, ref.path, out.path]));
        }
        if (allowed.contains(ImageFormat.webp) && tools.has(NativeTool.cwebp) && tools.has(NativeTool.dwebp) && _fitsWebp(analysis)) {
          await search.lossy(ImageFormat.webp, _webpQualities, (q) => 'WebP q$q', (q, out) {
            return tools.run(NativeTool.cwebp, [
              '-quiet',
              '-q',
              '$q',
              '-m',
              '6',
              '-sharp_yuv',
              '-metadata',
              metadata,
              if (analysis.hasAlpha) ...['-alpha_q', '100', '-alpha_filter', 'best'],
              ref.path,
              '-o',
              out.path,
            ]);
          });
          if (losslessSource) {
            await search.lossy(ImageFormat.webp, _nearLosslessLevels, (l) => 'WebP near-lossless $l', (l, out) => tools.run(NativeTool.cwebp, ['-quiet', '-near_lossless', '$l', '-z', '6', '-metadata', metadata, ref.path, '-o', out.path]));
          }
        }
        if (allowed.contains(ImageFormat.jpeg) && !analysis.hasAlpha) {
          if (tools.has(NativeTool.cjpegli)) {
            await search.lossy(ImageFormat.jpeg, _jpegliDistances, (d) => 'jpegli d$d', (d, out) => tools.run(NativeTool.cjpegli, [ref.path, out.path, '-d', '$d']));
          }
          // El PPM/PGM no lleva ICC.
          if (!keepIcc && tools.has(NativeTool.mozjpeg)) {
            final pnm = File(p.join(work.path, 'ref.pnm'));
            await pnm.writeAsBytes(analysis.referencePnm!);
            await search.lossy(ImageFormat.jpeg, _mozjpegQualities, (q) => 'mozjpeg q$q', (q, out) => tools.run(NativeTool.mozjpeg, ['-quality', '$q', '-outfile', out.path, pnm.path]));
          }
        }
      }

      if (search.candidates.isEmpty) {
        return const OptimizationOutcome.failed('Ningún formato de destino pudo codificar la imagen');
      }
      // A igual peso gana el que no tiene pérdida.
      final best = search.candidates.reduce((a, b) => b.size < a.size || (b.size == a.size && a.lossy && !b.lossy) ? b : a);
      if (best.method == 'original') return OptimizationOutcome.unchanged(size: bytes.length);

      await outputDir.create(recursive: true);
      return OptimizationOutcome.optimized(
        sourceFormat: source,
        originalSize: bytes.length,
        newSize: best.size,
        format: best.format,
        method: best.method,
        resultPath: (await best.file.copy(p.join(outputDir.path, '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}.${best.format.extension}'))).path,
        score: best.score,
        alphaRemoved: analysis.alphaRemoved,
      );
    } on NativeToolException catch (e) {
      return OptimizationOutcome.failed(e.message);
    } on FormatException catch (e) {
      return OptimizationOutcome.failed(e.message);
    } finally {
      await work.delete(recursive: true).catchError((_) => work);
    }
  }

  static bool _fitsWebp(ImageAnalysis a) => max(a.width, a.height) <= 16383;
}

class _Candidate {
  _Candidate(this.file, this.format, this.method, {required this.size, this.lossy = false, this.score});

  final File file;
  final ImageFormat format;
  final String method;
  final int size;
  final bool lossy;
  final double? score;
}

class _CandidateSearch {
  _CandidateSearch(this._tools, this._work, this._ref, this._threshold);

  final NativeToolset _tools;
  final Directory _work;
  final File _ref;
  final double _threshold;
  final candidates = <_Candidate>[];
  var _counter = 0;

  File _next(String extension) => File(p.join(_work.path, 'c${_counter++}.$extension'));

  int get _bestSize => candidates.isEmpty ? 1 << 62 : candidates.map((c) => c.size).reduce(min);

  Future<void> lossless(ImageFormat format, String method, Future<void> Function(File out) encode) async {
    final out = _next(format.extension);
    try {
      await encode(out);
    } on NativeToolException {
      return;
    }
    candidates.add(_Candidate(out, format, method, size: await out.length()));
  }

  // Búsqueda binaria sobre [params] (de mejor a peor calidad) del ajuste más
  // agresivo que mantiene la puntuación sobre el umbral.
  Future<void> lossy<T>(ImageFormat format, List<T> params, String Function(T param) label, Future<void> Function(T param, File out) encode) async {
    var lo = 0;
    var hi = params.length - 1;
    _Candidate? found;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      final out = _next(format.extension);
      try {
        await encode(params[mid], out);
      } on NativeToolException {
        hi = mid - 1;
        continue;
      }
      final size = await out.length();
      if (size >= _bestSize) {
        lo = mid + 1;
        continue;
      }
      final score = await _score(out, format);
      if (score >= _threshold) {
        found = _Candidate(out, format, label(params[mid]), size: size, lossy: true, score: (score * 100).roundToDouble() / 100);
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (found != null) candidates.add(found);
  }

  // ssimulacra2 no lee WebP ni AVIF.
  Future<double> _score(File candidate, ImageFormat format) async {
    try {
      var target = candidate;
      if (format == ImageFormat.webp) {
        target = _next('png');
        await _tools.run(NativeTool.dwebp, [candidate.path, '-png', '-o', target.path]);
      } else if (format == ImageFormat.avif) {
        target = _next('png');
        await _tools.run(NativeTool.avifdec, [candidate.path, target.path]);
      }
      return double.tryParse((await _tools.run(NativeTool.ssimulacra2, [_ref.path, target.path])).trim().split(RegExp(r'\s+')).last) ?? double.negativeInfinity;
    } on NativeToolException {
      return double.negativeInfinity;
    }
  }
}
