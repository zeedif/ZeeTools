import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zeetools/common/epub/models/epub_failure.dart';
import 'package:zeetools/common/epub/models/epub_manifest_item.dart';
import 'package:zeetools/common/process/native_tools_repo.dart';
import 'package:zeetools/common/utils/either.dart';
import 'package:zeetools/common/widgets/speed_dial.dart';
import 'package:zeetools/features/image_optimizer/data/image_optimizer_repo.dart';
import 'package:zeetools/features/image_optimizer/data/image_optimizer_settings_repo.dart';
import 'package:zeetools/features/image_optimizer/domain/image_format.dart';
import 'package:zeetools/features/image_optimizer/domain/optimization_options.dart';
import 'package:zeetools/features/image_optimizer/domain/optimization_outcome.dart';
import 'package:zeetools/features/image_optimizer/domain/source_image.dart';
import 'package:zeetools/features/image_optimizer/presentation/cubit/image_optimizer_cubit.dart';
import 'package:zeetools/features/image_optimizer/presentation/views/image_optimizer_view.dart';
import 'package:zeetools/inject_dependencies.dart';

// Repositorio falso: cada imagen "se optimiza" a la mitad en WebP, salvo las
// .gif (omitidas por animadas) y las que contienen "fail" en el nombre.
class _FakeRepo implements ImageOptimizerRepository {
  final applied = <String>[];

  OptimizationOutcome _outcomeFor(String name) {
    if (name.endsWith('.gif')) return const OptimizationOutcome.skipped('Imagen animada');
    if (name.contains('fail')) return const OptimizationOutcome.failed('cwebp falló');
    return const OptimizationOutcome.optimized(sourceFormat: ImageFormat.png, originalSize: 200000, newSize: 100000, format: ImageFormat.webp, method: 'WebP sin pérdida', resultPath: 'resultado.webp', alphaRemoved: true);
  }

  @override
  Future<ScanResult> scan(List<String> paths, {required bool recursive}) async => ScanResult(images: paths.where((p) => !p.endsWith('.epub')).toList(), epubs: paths.where((p) => p.endsWith('.epub')).toList());

  @override
  Future<SourceImage> describeImage(String path) async => SourceImage(path: path, size: 200000, format: ImageFormat.png);

  @override
  Future<Either<EpubFailure, List<EpubManifestItem>>> loadEpubImages(String epubPath) async => Either.right([
    for (final (i, name) in ['portada.png', 'mapa.jpg', 'anim.gif', 'logo fail.png'].indexed)
      EpubManifestItem(
        id: 'img$i',
        href: 'images/$name',
        archivePath: 'OEBPS/images/$name',
        mediaType: ImageFormat.values.firstWhere((f) => name.endsWith(f.extension), orElse: () => ImageFormat.png).mediaType,
        properties: i == 0 ? 'cover-image' : '',
      ),
  ]);

  @override
  void unloadEpub(String epubPath) {}

  @override
  Future<NativeToolset> ensureTools({void Function(String message)? onProgress}) async => const NativeToolset({});

  @override
  Future<OptimizationOutcome> optimizeFile(String path, OptimizationOptions options, NativeToolset tools) async => _outcomeFor(path);

  @override
  Future<OptimizationOutcome> optimizeEpubImage(String epubPath, EpubManifestItem item, OptimizationOptions options, NativeToolset tools) async => _outcomeFor(item.href);

  @override
  Future<Either<EpubFailure, EpubManifestItem>> applyToEpub(String epubPath, EpubManifestItem item, OptimizedOutcome outcome) async {
    applied.add(item.href);
    final href = item.href.replaceFirst(RegExp(r'\.\w+$'), '.webp');
    return Either.right(item.copyWith(href: href, archivePath: 'OEBPS/$href', mediaType: outcome.format.mediaType));
  }

  @override
  Future<String> saveImage(SourceImage image, OptimizedOutcome outcome, {String? targetDir}) async => image.path.replaceFirst(RegExp(r'\.\w+$'), '.webp');

  @override
  Future<String> copyOriginal(SourceImage image, String targetDir) async => image.path;

  @override
  Future<Either<EpubFailure, void>> saveEpub(String epubPath) async => const Either.right(null);

  @override
  Future<Either<EpubFailure, Uint8List>> encodeEpub(String epubPath) async => Either.right(Uint8List(0));

  @override
  Future<void> discardResult(OptimizationOutcome outcome) async {}
}

void main() {
  late _FakeRepo repo;
  late ImageOptimizerCubit cubit;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await getIt.reset();
    repo = _FakeRepo();
    cubit = ImageOptimizerCubit(repo, ImageOptimizerSettingsRepositoryImpl(prefs));
    getIt.registerFactory<ImageOptimizerCubit>(() => cubit);
    getIt.registerLazySingleton<ValueNotifier<List<SpeedDialAction>>>(() => ValueNotifier([]));
  });

  Future<void> pumpView(WidgetTester tester, {Size size = const Size(1280, 800)}) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(const MaterialApp(home: ImageOptimizerView()));
    await tester.pumpAndSettle();
  }

  testWidgets('imágenes sueltas: carga, optimiza y guarda en sitio', (tester) async {
    await pumpView(tester);
    expect(find.text('Arrastra aquí imágenes, EPUBs o carpetas'), findsOneWidget);

    await tester.runAsync(() => cubit.open(ImageSessionKind.images, ['C:/img/a.png', 'C:/img/b fail.png', 'C:/img/c.gif']));
    await tester.pumpAndSettle();
    expect(find.text('a.png'), findsOneWidget);
    expect(find.text('Pendiente'), findsNWidgets(3));

    await tester.tap(find.text('Optimizar'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('−50.0%'), findsOneWidget);
    expect(find.text('Omitida: Imagen animada'), findsOneWidget);
    expect(find.text('Error'), findsOneWidget);

    await tester.runAsync(cubit.saveImagesInPlace);
    await tester.pumpAndSettle();
    expect(find.text('a.webp'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    // Quitar de la lista
    await tester.tap(find.byTooltip('Quitar de la lista').at(1));
    await tester.pumpAndSettle();
    expect(find.text('b fail.png'), findsNothing);
  });

  testWidgets('varios EPUBs: lista, foco en uno, selección por formato y aplicación en memoria', (tester) async {
    await pumpView(tester);
    await tester.runAsync(() => cubit.open(ImageSessionKind.epubs, ['C:/libros/uno.epub', 'C:/libros/dos.epub']));
    await tester.pumpAndSettle();
    expect(find.text('uno.epub'), findsWidgets);
    expect(find.text('EPUBs (2) · 8 imágenes'), findsOneWidget);

    // Solo PNG en todos los EPUBs.
    await tester.tap(find.text('PNG').first);
    await tester.pumpAndSettle();
    expect(find.text('EPUBs (2) · 4/8 activas'), findsOneWidget);

    await tester.tap(find.text('Optimizar'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(repo.applied, ['images/portada.png', 'images/portada.png']);
    expect(find.byTooltip('Cambios sin guardar'), findsNWidgets(2));

    // Entrar a un EPUB y volver.
    await tester.tap(find.byTooltip('Elegir imágenes').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Volver · 2 EPUBs'), findsOneWidget);
    expect(find.text('portada.webp'), findsWidgets);
    await tester.tap(find.textContaining('Volver · 2 EPUBs'));
    await tester.pumpAndSettle();

    // Quitar un EPUB deja la vista individual del restante.
    await tester.tap(find.byTooltip('Quitar').first);
    await tester.pumpAndSettle();
    expect(find.text('Imágenes · 4'), findsNothing);
    expect(find.textContaining('/4 imágenes'), findsOneWidget);
  });

  testWidgets('ventana estrecha: las vistas no desbordan', (tester) async {
    await pumpView(tester, size: const Size(640, 600));
    await tester.runAsync(() => cubit.open(ImageSessionKind.epubs, ['C:/libros/un libro con un nombre bastante largo.epub', 'C:/libros/dos.epub']));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Optimizar'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Elegir imágenes').first);
    await tester.pumpAndSettle();
    await tester.runAsync(cubit.resetToIdle);
    await tester.runAsync(() => cubit.open(ImageSessionKind.images, ['C:/img/una imagen con nombre muy largo para probar.png']));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Optimizar'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
