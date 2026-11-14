import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';

import '/common/utils/either.dart';
import '../domain/migration_project.dart';
import 'epub_archive.dart';
import 'migration_analyzer.dart';
import 'migration_writer.dart';

const _assetDir = 'assets/epub_templater';
const _oldTemplatesDir = 'assets/epub_migrator/old_templates';

typedef OpenedEpub = ({Uint8List bytes, EpubArchive archive, MigrationProject project});

abstract interface class EpubMigratorRepository {
  Future<Either<String, OpenedEpub>> open(String path);
  Future<Either<String, MigratedEpub>> migrate(Uint8List source, MigrationProject project);
}

class EpubMigratorRepositoryImpl implements EpubMigratorRepository {
  @override
  Future<Either<String, OpenedEpub>> open(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final css = await rootBundle.loadString('$_assetDir/style.css');
      // El análisis puede tardar con libros grandes; el archivo se vuelve a leer aquí para las vistas previas.
      final oldTemplates = (latest: await rootBundle.loadString('$_oldTemplatesDir/latest.css'), earlier: await rootBundle.loadString('$_oldTemplatesDir/earlier.css'));
      final project = await Isolate.run(() => analyzeEpub(path, EpubArchive.decode(bytes), templateCss: css, oldTemplates: oldTemplates));
      return Either.right((bytes: bytes, archive: EpubArchive.decode(bytes), project: project));
    } on FormatException catch (e) {
      return Either.left('No es un EPUB válido: ${e.message}');
    } catch (e) {
      return Either.left('No se pudo abrir el EPUB: $e');
    }
  }

  @override
  Future<Either<String, MigratedEpub>> migrate(Uint8List source, MigrationProject project) async {
    try {
      final css = await rootBundle.loadString('$_assetDir/style.css');
      final navCss = await rootBundle.loadString('$_assetDir/nav-style.css');
      final logo = (await rootBundle.load('$_assetDir/zeepubs.png')).buffer.asUint8List();
      return Either.right(await Isolate.run(() => writeMigratedEpub(EpubArchive.decode(source), project, templateCss: css, navCss: navCss, zeepubsLogo: logo)));
    } catch (e) {
      return Either.left('No se pudo migrar el EPUB: $e');
    }
  }
}
