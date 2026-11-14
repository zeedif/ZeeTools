import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:zeetools/features/epub_migrator/data/epub_archive.dart';
import 'package:zeetools/features/epub_migrator/data/legacy_styles.dart';
import 'package:zeetools/features/epub_migrator/data/migration_analyzer.dart';
import 'package:zeetools/features/epub_migrator/data/migration_writer.dart';
import 'package:zeetools/features/epub_migrator/domain/migration_issues.dart';
import 'package:zeetools/features/epub_migrator/domain/migration_kind.dart';
import 'package:zeetools/features/epub_migrator/domain/migration_project.dart';
import 'package:zeetools/features/epub_templater/domain/book_metadata.dart';
import 'package:zeetools/features/epub_templater/domain/section_kind.dart';

import 'helpers/old_template_epub.dart';

final _templateCss = File('assets/epub_templater/style.css').readAsStringSync();

MigrationProject _analyze() => analyzeEpub('C:/libros/mi novela.epub', EpubArchive.decode(oldTemplateEpub()), templateCss: _templateCss);

Map<String, String> _write(MigrationProject project) {
  final result = writeMigratedEpub(
    EpubArchive.decode(oldTemplateEpub()),
    project,
    templateCss: _templateCss,
    navCss: File('assets/epub_templater/nav-style.css').readAsStringSync(),
    zeepubsLogo: testPng,
    now: DateTime.utc(2026, 10, 6),
  );
  final archive = ZipDecoder().decodeBytes(result.bytes);
  expect(archive.files.first.name, 'mimetype');
  return {for (final f in archive.files) f.name: f.name.endsWith('.png') ? '' : utf8.decode(f.content)};
}

void main() {
  test('clasifica, une las partes del capítulo y propone los nombres del template', () {
    final project = _analyze();
    expect([for (final d in project.docs) (d.kind, d.continuation, d.fileName)], [
      (MigrationKind.cover, false, 'cubierta'),
      (MigrationKind.chapter, false, 'capitulo01'),
      (MigrationKind.chapter, true, 'capitulo01'),
      (MigrationKind.endnotes, false, 'notas'),
    ]);
    expect(project.docs[1].label, 'Capítulo 1: El inicio');
    expect([for (final d in project.docs) d.matter], [BookMatter.front, BookMatter.body, BookMatter.body, BookMatter.back]);
  });

  test('clases antiguas, reglas propias, fecha invertida, ISBN y título en español', () {
    final project = _analyze();
    expect(project.classRenames, containsPair('centrado', ['align-center']));
    expect(project.classRenames, containsPair('dimg', ['fill']));
    expect(project.classRenames, containsPair('salto1', ['space-1']));
    expect(project.customCss, contains('.carta {\n  font-style: italic;\n}'));
    expect(project.unknownClasses, isEmpty);
    expect(project.metadata.date, '2017-03-25T00:00:00Z');
    expect((project.metadata.isbn13, project.metadata.isbn10), ('978-40-4685-088-1', '40-4685-088-4'));
    expect(project.metadata.altTitles, const [LocalizedText(lang: 'es', text: 'Mi novela - Volumen 01')]);
    expect(project.readIssues.map((i) => i.message), contains('Es image/png aunque se declara image/jpeg; se corrige en el OPF.'));
  });

  test('pendientes: el título principal debe ir en inglés; el resto no bloquea', () {
    final project = _analyze();
    final errors = migrationIssues(project).where((i) => i.level == MigrationIssueLevel.error).map((i) => i.message).toList();
    expect(errors, ['El título principal está en «es»: escríbelo en inglés.']);
    final fixed = project.copyWith(metadata: project.metadata.copyWith(title: 'My Novel - Volumen 01 [MN]', titleLang: 'en'));
    expect(migrationIssues(fixed).where((i) => i.level == MigrationIssueLevel.error), isEmpty);
    final duplicated = fixed.copyWith(docs: [for (final d in fixed.docs) d.kind == MigrationKind.endnotes ? d.copyWith(fileName: 'capitulo01') : d]);
    expect(migrationIssues(duplicated).map((i) => i.message), contains('El archivo «capitulo01» está repetido.'));
  });

  test('escribe la estructura del template: secciones, notas, índice, OPF y estilos', () {
    final project = _analyze();
    final files = _write(project.copyWith(metadata: project.metadata.copyWith(title: 'My Novel - Volumen 01 [MN]', titleLang: 'en')));
    expect(files.keys, containsAll(['OEBPS/Text/cubierta.xhtml', 'OEBPS/Text/capitulo01.xhtml', 'OEBPS/Text/notas.xhtml', 'OEBPS/Text/logos.xhtml', 'OEBPS/Text/toc.xhtml', 'OEBPS/Styles/nav-style.css', 'OEBPS/Images/zeepubs.png']));
    expect(files.keys, isNot(contains('OEBPS/Text/Section0001-2.xhtml')));
    for (final MapEntry(key: path, value: text) in files.entries) {
      if (RegExp(r'\.(xhtml|opf)$').hasMatch(path)) expect(() => XmlDocument.parse(text), returnsNormally, reason: path);
    }

    final chapter = files['OEBPS/Text/capitulo01.xhtml']!;
    expect(chapter, contains('<section epub:type="chapter" role="doc-chapter" aria-labelledby="encabezado">'));
    expect(chapter, contains('<h1 class="hidden" id="encabezado">Capítulo 1: El inicio</h1>'));
    expect(chapter, contains('<figure class="fill break-after">'));
    expect(chapter, contains('<h1 class="sigil_not_in_toc" id="Section0001-2">Capítulo 1<br/><small>El inicio</small></h1>'));
    expect(chapter, contains('<p class="align-center space-1 carta">Texto<a href="notas.xhtml#nt1" id="rf1" epub:type="noteref" role="doc-noteref">'));
    expect(chapter, contains('<span class="large">Grande</span> y <strong>error</strong>'));
    expect(chapter, isNot(contains('<header>')));

    final notes = files['OEBPS/Text/notas.xhtml']!;
    expect(notes, contains('<section epub:type="endnotes" role="doc-endnotes" aria-labelledby="encabezado">'));
    expect(notes, contains('<ol class="notes"><li id="nt1"><p><a href="capitulo01.xhtml#rf1" role="doc-backlink"><sup>1</sup></a> Una nota.</p></li></ol>'));

    final nav = files['OEBPS/Text/toc.xhtml']!;
    expect(nav, contains('<a href="cubierta.xhtml">Cubierta</a>'));
    expect(nav, contains('<a href="capitulo01.xhtml">Capítulo 1: El inicio</a>'));

    final opf = files['OEBPS/content.opf']!;
    expect(opf, contains('<dc:title id="title" xml:lang="en">My Novel - Volumen 01 [MN]</dc:title>'));
    expect(opf, contains('href="Images/cover.png" media-type="image/png" properties="cover-image"'));
    expect(opf, contains('properties="nav"'));
    expect(opf, isNot(contains('Section0001')));

    expect(files['OEBPS/Styles/style.css'], endsWith('.carta {\n  font-style: italic;\n}\n'));
  });

  test('una sección separada a mano conserva su archivo y su entrada en el índice', () {
    final project = _analyze();
    final split = project.copyWith(
      metadata: project.metadata.copyWith(title: 'My Novel', titleLang: 'en'),
      docs: [for (final d in project.docs) d.continuation ? d.copyWith(continuation: false, inToc: true, fileName: 'capitulo02', label: 'Capítulo 2') : d],
    );
    final files = _write(split);
    expect(files.keys, contains('OEBPS/Text/capitulo02.xhtml'));
    expect(files['OEBPS/Text/capitulo01.xhtml'], isNot(contains('Texto')));
    expect(files['OEBPS/Text/notas.xhtml'], contains('href="capitulo02.xhtml#rf1"'));
    expect(files['OEBPS/Text/toc.xhtml'], contains('<a href="capitulo02.xhtml">Capítulo 2</a>'));
  });

  test('lo que el libro cambió sobre el template anterior va al final de la hoja', () {
    // Git puede entregar la hoja con finales de línea de Windows.
    String read(String name) => File('assets/epub_migrator/old_templates/$name.css').readAsStringSync().replaceAll('\r\n', '\n');
    final oldTemplates = (latest: read('latest'), earlier: read('earlier'));
    final edited = oldTemplates.latest
        .replaceFirst('p {\n  text-indent: 0;', 'p {\n  text-indent: 1.5em;')
        .replaceFirst('h2 {\n  font-size: 1.3750em;', 'h2 {\n  text-align: left;\n  font-size: 1.3750em;')
        .replaceFirst('h2.subtitulo {\n  font-family: sans-serif;', 'h2.subtitulo {\n  text-align: center;');
    expect(edited, isNot(oldTemplates.latest));
    final project = analyzeEpub('C:/libros/mi novela.epub', EpubArchive.decode(oldTemplateEpub(styleCss: edited)), templateCss: _templateCss, oldTemplates: oldTemplates);
    final adjustments = project.customCss.split('/* Ajustes de este libro sobre el template */').last;
    expect(adjustments, contains('p {\n  text-indent: 1.5em;\n}'));
    expect(adjustments, contains('h2 {\n  text-align: left;\n}'));
    // Una regla cuya clase no aparece en el libro no se lleva.
    expect(adjustments, isNot(contains('subtitle')));
    // El subtítulo deja de heredar el centrado de h2: su valor propio se reafirma aunque coincida con el del template.
    final deltas = legacyDeltas(edited, oldTemplates).where((d) => d.selector == 'h2.subtitulo' && d.property == 'text-align');
    expect([for (final d in deltas) (d.value, d.removed)], [('center', false)]);
    // Las clases de sangría del template siguen ganando a la regla de p.
    expect(adjustments, isNot(contains('no-indent')));

    final untouched = analyzeEpub('C:/libros/mi novela.epub', EpubArchive.decode(oldTemplateEpub(styleCss: oldTemplates.latest)), templateCss: _templateCss, oldTemplates: oldTemplates);
    expect(untouched.customCss, isNot(contains('Ajustes de este libro')));

    // Un libro hecho con una versión previa se compara con ella, no con la última.
    expect(legacyDeltas('.borde { border: 0.0625em solid currentColor; padding: 0.6875em; }', oldTemplates), isEmpty);
    expect(legacyDeltas('.borde { border: 0.0625em solid currentColor; padding: 0 0.6875em; }', oldTemplates), isEmpty);
  });

  test('quitar el display del template devuelve el elemento al que le da el lector', () {
    final base = StyleSheetValues('table {\n  display: table;\n  margin: 1em;\n}\n.marco {\n  display: block;\n  color: red;\n}');
    final book = StyleSheetValues('table {\n  margin: 1em;\n}\n.marco {\n  color: red;\n}');
    final display = [for (final d in diffStyles(book, base)) if (d.property == 'display') d];
    // La tabla sigue siendo una tabla y de una clase sola no se sabe qué elemento es: no hay nada que trasladar.
    expect(display, isEmpty);
  });
}
