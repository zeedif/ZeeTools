// ignore_for_file: avoid_print

// Prueba de humo del optimizador de imágenes sin interfaz: descarga las CLIs
// (la primera vez), optimiza imágenes generadas en ambos modos de calidad y
// procesa un EPUB sintético comprobando que el OPF y las referencias desde
// XHTML, CSS y SVG apunten a los recursos renombrados.
//
// dart run --enable-experiment=primary-constructors tool/smoke_test_image_optimizer.dart <carpeta-de-trabajo>
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:zeetools/common/epub/repositories/epub_repo.dart';
import 'package:zeetools/common/process/native_tools_repo.dart';
import 'package:zeetools/common/utils/either.dart';
import 'package:zeetools/features/image_optimizer/data/image_optimizer_engine.dart';
import 'package:zeetools/features/image_optimizer/data/image_optimizer_repo.dart';
import 'package:zeetools/features/image_optimizer/domain/image_format.dart';
import 'package:zeetools/features/image_optimizer/domain/optimization_options.dart';
import 'package:zeetools/features/image_optimizer/domain/optimization_outcome.dart';

Future<void> main(List<String> args) async {
  final workDir = Directory(args.isNotEmpty ? args.first : p.join(Directory.systemTemp.path, 'zeetools_smoke'));
  await workDir.create(recursive: true);

  final toolsRepo = NativeToolsRepositoryImpl(p.join(workDir.path, 'tools'));
  final tools = await toolsRepo.ensureTools(onProgress: print);
  print('Herramientas faltantes: ${tools.missing.map((t) => t.command).toList()}');

  final samples = _samples();
  final engine = ImageOptimizerEngine();
  final outDir = Directory(p.join(workDir.path, 'out'));
  for (final mode in QualityMode.values) {
    for (final allowed in [ImageFormat.defaultOutputs.toSet(), ImageFormat.outputs.toSet()]) {
      print('\n== ${mode.label} · ${allowed.map((f) => f.label).join('/')}');
      for (final MapEntry(key: name, value: bytes) in samples.entries) {
        final sw = Stopwatch()..start();
        final outcome = await engine.optimize(
          bytes,
          tools: tools,
          options: OptimizationOptions(allowedFormats: allowed, qualityMode: mode),
          outputDir: outDir,
        );
        print('  $name (${bytes.length} B): ${_describe(outcome)} [${sw.elapsedMilliseconds} ms]');
      }
    }
  }

  print('\n== Reglas de formato');
  final staticGif = img.encodeGif(img.Image(width: 64, height: 64)..clear(img.ColorRgb8(200, 30, 30)));
  final rules = <(String, Uint8List, OptimizationOptions)>[
    ('PNG con transparencia, solo JPEG como destino', samples['logo-transparente.png']!, const OptimizationOptions(allowedFormats: {ImageFormat.jpeg}, qualityMode: QualityMode.visuallyLossless)),
    ('PNG con alfa sin uso, solo JPEG como destino', samples['ilustracion-alfa-sin-uso.png']!, const OptimizationOptions(allowedFormats: {ImageFormat.jpeg}, qualityMode: QualityMode.visuallyLossless)),
    ('PNG sin conversión (todos los destinos marcados)', samples['ilustracion-alfa-sin-uso.png']!, OptimizationOptions(allowedFormats: ImageFormat.outputs.toSet(), allowConversion: false, qualityMode: QualityMode.visuallyLossless)),
    ('JPEG sin conversión', samples['foto.jpg']!, OptimizationOptions(allowedFormats: ImageFormat.outputs.toSet(), allowConversion: false, qualityMode: QualityMode.visuallyLossless)),
    ('JPEG sin destinos marcados', samples['foto.jpg']!, const OptimizationOptions(allowedFormats: {}, qualityMode: QualityMode.lossless)),
    ('GIF estático sin conversión', staticGif, const OptimizationOptions(allowedFormats: {ImageFormat.png}, allowConversion: false, qualityMode: QualityMode.lossless)),
    ('GIF estático con conversión', staticGif, const OptimizationOptions(allowedFormats: {ImageFormat.png, ImageFormat.webp}, qualityMode: QualityMode.lossless)),
  ];
  for (final (label, bytes, options) in rules) {
    final outcome = await engine.optimize(bytes, tools: tools, options: options, outputDir: outDir);
    print('  $label: ${_describe(outcome)}');
  }

  await _epubFlow(workDir, toolsRepo, tools, samples);
}

String _describe(OptimizationOutcome o) => switch (o) {
  OptimizedOutcome(:final sourceFormat, :final newSize, :final format, :final method, :final score, :final alphaRemoved) => '→ $newSize B ${sourceFormat.label}→${format.label} [$method${score != null ? ', ss2=$score' : ''}${alphaRemoved ? ', alfa eliminado' : ''}]',
  UnchangedOutcome() => 'sin cambios',
  SkippedOutcome(:final reason) => 'omitida: $reason',
  FailedOutcome(:final message) => 'ERROR: $message',
};

Map<String, Uint8List> _samples() {
  final rnd = Random(1);
  // Ilustración: degradados + figuras + algo de ruido, con alfa opaco (sin uso).
  final art = img.Image(width: 640, height: 480, numChannels: 4);
  for (final px in art) {
    final x = px.x, y = px.y;
    final ring = ((x - 320) * (x - 320) + (y - 240) * (y - 240)) < 150 * 150;
    px
      ..r = ring ? 220 : (x * 255 ~/ 640)
      ..g = ring ? 40 : (y * 255 ~/ 480)
      ..b = (128 + rnd.nextInt(24)).clamp(0, 255)
      ..a = 255;
  }
  // Escala de grises con texto simulado (rayas finas).
  final gray = img.Image(width: 400, height: 300);
  for (final px in gray) {
    final v = (px.y % 6 < 2 && px.x % 40 < 30) ? 20 : 235;
    px
      ..r = v
      ..g = v
      ..b = v;
  }
  // Logo con transparencia real.
  final logo = img.Image(width: 300, height: 120, numChannels: 4);
  for (final px in logo) {
    final inside = (px.x - 150).abs() < 120 && (px.y - 60).abs() < 40;
    px
      ..r = 30
      ..g = 90
      ..b = 200
      ..a = inside ? 255 : 0;
  }
  final anim = img.Image(width: 32, height: 32)..addFrame(img.Image(width: 32, height: 32));

  return {
    'ilustracion-alfa-sin-uso.png': img.encodePng(art),
    'grises.png': img.encodePng(gray),
    'logo-transparente.png': img.encodePng(logo),
    'foto.jpg': img.encodeJpg(art, quality: 97),
    'animada.gif': img.encodeGif(anim),
  };
}

Future<void> _epubFlow(Directory workDir, NativeToolsRepository toolsRepo, NativeToolset tools, Map<String, Uint8List> samples) async {
  print('\n== EPUB');
  final epubPath = p.join(workDir.path, 'prueba.epub');
  File(epubPath).writeAsBytesSync(_buildEpub(samples));

  final repo = ImageOptimizerRepositoryImpl(EpubRepositoryImpl(), toolsRepo, ImageOptimizerEngine());
  final images = (await repo.loadEpubImages(epubPath)).getOrElse((f) => throw StateError('$f'));
  print('Imágenes en el manifiesto: ${images.map((i) => i.href).toList()}');

  const options = OptimizationOptions(allowedFormats: {ImageFormat.jpeg, ImageFormat.png, ImageFormat.webp}, qualityMode: QualityMode.visuallyLossless);
  for (final item in images) {
    final outcome = await repo.optimizeEpubImage(epubPath, item, options, tools);
    print('  ${item.href}: ${_describe(outcome)}');
    if (outcome is OptimizedOutcome) {
      final applied = await repo.applyToEpub(epubPath, item, outcome);
      print('    → ${applied.fold((f) => 'ERROR $f', (i) => '${i.href} (${i.mediaType})')}');
    }
  }

  final bytes = (await repo.encodeEpub(epubPath)).getOrElse((f) => throw StateError('$f'));
  final outPath = p.join(workDir.path, 'prueba-optimizada.epub');
  File(outPath).writeAsBytesSync(bytes);
  final archive = ZipDecoder().decodeBytes(bytes);
  final first = archive.files.first;
  print('Primera entrada: ${first.name} (${first.compression})');
  for (final name in ['OEBPS/content.opf', 'OEBPS/text/cap1.xhtml', 'OEBPS/styles/estilo.css', 'OEBPS/text/portada.xhtml']) {
    print('--- $name\n${utf8.decode(archive.findFile(name)!.content)}');
  }
  print('Entradas: ${archive.files.map((f) => f.name).toList()}');
  print('EPUB optimizado: $outPath (${File(epubPath).lengthSync()} → ${bytes.length} B)');
}

Uint8List _buildEpub(Map<String, Uint8List> samples) {
  final archive = Archive()..addFile(ArchiveFile.noCompress('mimetype', 20, utf8.encode('application/epub+zip')));
  void text(String name, String content) {
    final data = utf8.encode(content);
    archive.addFile(ArchiveFile(name, data.length, data));
  }

  void binary(String name, Uint8List data) => archive.addFile(ArchiveFile.noCompress(name, data.length, data));

  text('META-INF/container.xml', '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''');
  text('OEBPS/content.opf', '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:00000000-0000-0000-0000-000000000000</dc:identifier>
    <dc:title>Prueba</dc:title><dc:language>es</dc:language>
    <meta property="dcterms:modified">2026-10-03T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="text/nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="portada" href="text/portada.xhtml" media-type="application/xhtml+xml" properties="svg"/>
    <item id="cap1" href="text/cap1.xhtml" media-type="application/xhtml+xml"/>
    <item id="css" href="styles/estilo.css" media-type="text/css"/>
    <item id="cover" href="images/ilustracion.png" media-type="image/png" properties="cover-image"/>
    <item id="gris" href="images/grises.png" media-type="image/png"/>
    <item id="logo" href="images/logo%20transparente.png" media-type="image/png"/>
    <item id="foto" href="images/foto.jpg" media-type="image/jpeg"/>
    <item id="anim" href="images/animada.gif" media-type="image/gif"/>
  </manifest>
  <spine><itemref idref="portada"/><itemref idref="cap1"/></spine>
</package>''');
  text('OEBPS/text/nav.xhtml', '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Índice</title></head>
<body><nav epub:type="toc"><ol><li><a href="cap1.xhtml">Capítulo 1</a></li></ol></nav></body></html>''');
  text('OEBPS/text/portada.xhtml', '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Portada</title></head>
<body><svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 640 480"><image width="640" height="480" xlink:href="../images/ilustracion.png"/></svg></body></html>''');
  text('OEBPS/text/cap1.xhtml', '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Capítulo 1</title><link rel="stylesheet" href="../styles/estilo.css"/></head>
<body>
  <p><img src="../images/grises.png" alt="grises"/></p>
  <p><img src="../images/foto.jpg" srcset="../images/foto.jpg 1x, ../images/ilustracion.png 2x" alt="foto"/></p>
  <p style="background-image: url('../images/logo%20transparente.png')"><img src="../images/animada.gif" alt="anim"/></p>
  <p><a href="cap1.xhtml#arriba">enlace interno</a> <a href="https://example.com/images/foto.jpg">externo</a></p>
</body></html>''');
  text('OEBPS/styles/estilo.css', '''body { background: url("../images/grises.png") repeat; }
.logo { background-image: url(../images/logo%20transparente.png); }''');
  binary('OEBPS/images/ilustracion.png', samples['ilustracion-alfa-sin-uso.png']!);
  binary('OEBPS/images/grises.png', samples['grises.png']!);
  binary('OEBPS/images/logo transparente.png', samples['logo-transparente.png']!);
  binary('OEBPS/images/foto.jpg', samples['foto.jpg']!);
  binary('OEBPS/images/animada.gif', samples['animada.gif']!);
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
