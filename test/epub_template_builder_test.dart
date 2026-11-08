import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:zeetools/common/utils/input_formatters.dart';
import 'package:zeetools/common/utils/uuid_v7.dart';
import 'package:zeetools/features/epub_templater/data/epub_template_builder.dart';
import 'package:zeetools/features/epub_templater/domain/book_metadata.dart';
import 'package:zeetools/features/epub_templater/domain/embedded_font.dart';
import 'package:zeetools/features/epub_templater/domain/marc_relator.dart';
import 'package:zeetools/features/epub_templater/domain/section_kind.dart';
import 'package:zeetools/features/epub_templater/domain/subjects.dart';
import 'package:zeetools/features/epub_templater/domain/template_project.dart';
import 'package:zeetools/features/epub_templater/domain/template_section.dart';
import 'package:zeetools/features/epub_templater/domain/title_languages.dart';

final _png = Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

Map<String, String> _build(TemplateProject project, {Map<String, Uint8List> images = const {}}) {
  final entries = EpubTemplateBuilder(
    project: project,
    styleCss: File('assets/epub_templater/style.css').readAsStringSync(),
    navCss: File('assets/epub_templater/nav-style.css').readAsStringSync(),
    images: images,
    zeepubsLogo: _png,
    now: DateTime.utc(2026, 10, 3, 12),
  ).build();
  expect(entries.first.path, 'mimetype');
  return {for (final e in entries) e.path: e.path.contains('/Images/') ? '' : utf8.decode(e.bytes)};
}

TemplateProject _project({BookMetadata Function(BookMetadata m)? metadata, List<TemplateSection>? sections}) {
  final base = TemplateProject.initial();
  final m = base.metadata.copyWith(
    identifier: uuidV7(),
    title: 'Mitsuba Monogatari - Volumen 03 [KT]',
    titleLang: 'ja-Latn',
    altTitles: const [
      LocalizedText(lang: 'ja-Latn', text: 'Repetido'),
      LocalizedText(lang: 'es', text: 'La Historia de Mitsuba'),
    ],
    actors: const [
      Actor(
        name: 'Nanasawa Matari',
        altNames: [LocalizedText(lang: 'ja', text: '七沢またり')],
        roles: [MarcRelator.aut],
      ),
      Actor(name: 'EURA', roles: [MarcRelator.ill]),
      Actor(name: 'Rin-san', roles: [MarcRelator.trl, MarcRelator.pfr]),
      Actor(roles: [MarcRelator.mrk]),
      Actor(name: 'ZeePubs', roles: [MarcRelator.dst]),
    ],
    publishers: const ['Kyuden Translations'],
    series: 'Mitsuba’s Stories [NL]',
    seriesIndex: '3',
    demographic: Demographic.seinen,
    genres: const ['Fantasía', 'Acción'],
  );
  return base.copyWith(metadata: metadata?.call(m) ?? m, sections: sections ?? base.sections);
}

void main() {
  test('uuidV7 tiene versión 7, variante RFC y empieza por la marca de tiempo', () {
    final at = DateTime.utc(2026, 10, 3);
    final id = uuidV7(at);
    expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(int.parse(id.replaceAll('-', '').substring(0, 12), radix: 16), at.millisecondsSinceEpoch);
  });

  test('valida ISBN-13 e ISBN-10 por dígito de control', () {
    expect(isValidIsbn13('978-4-04-685088-1'), isTrue);
    expect(isValidIsbn13('978-4-04-685088-2'), isFalse);
    expect(isValidIsbn10('4-04-685088-4'), isTrue);
    expect(isValidIsbn10('0-8044-2957-X'), isTrue);
    expect(isValidIsbn10('4-04-685088-5'), isFalse);
  });

  test('ISBN con los guiones del template y conversión entre 13 y 10 dígitos', () {
    expect(formatIsbn('9784046850881', isbn13Groups), '978-40-4685-088-1');
    expect(formatIsbn('978404', isbn13Groups), '978-40-4');
    expect(formatIsbn('404685088x', isbn10Groups), '40-4685-088-X');
    expect(isbn10From13('978-4-04-685088-1'), '4046850884');
    expect(isbn13From10('4-04-685088-4'), '9784046850881');
    expect(isbn10From13('979-10-90636-07-1'), isNull);
  });

  test('los enlaces de una misma etiqueta van juntos bajo ella, en el orden definido', () {
    final files = _build(_project(metadata: (m) => m.copyWith(links: const [
      WebLink(label: 'Redes sociales', url: 'https://x.com/a'),
      WebLink(label: 'Página Web', url: 'https://grupo.com'),
      WebLink(label: 'Redes sociales', url: 'https://facebook.com/a'),
      WebLink(label: 'Redes sociales', url: 'https://discord.gg/a'),
      WebLink(label: 'Distribuye', url: 'https://www.facebook.com/ZeePubs', text: 'ZeePubs'),
    ])));
    final title = files['OEBPS/Text/titulo.xhtml']!;
    expect(title, contains('<p class="space-1"><b>Redes sociales</b><br/><a href="https://x.com/a">https://x.com/a</a><br/><a href="https://facebook.com/a">https://facebook.com/a</a><br/><a href="https://discord.gg/a">https://discord.gg/a</a></p>'));
    expect(title.indexOf('Redes sociales'), lessThan(title.indexOf('Página Web')));
    expect('Redes sociales'.allMatches(title).length, 1);
    expect(title, contains('<a href="https://www.facebook.com/ZeePubs">ZeePubs</a>'));
  });

  test('créditos en el orden de las personas, con ruby, separadores, traducción y distribución junto al maquetador', () {
    final files = _build(
      _project(
        metadata: (m) => m.copyWith(
          actors: const [
            Actor(
              name: 'Kamachi Kazuma',
              altNames: [LocalizedText(lang: 'ja', text: '鎌池 和馬')],
              roles: [MarcRelator.aut],
            ),
            Actor(name: 'Haimura Kiyotaka', roles: [MarcRelator.ill], separated: true),
            Actor(name: 'js06', roles: [MarcRelator.trl], fromLang: 'ja', toLang: 'en'),
            Actor(name: 'Lestat', roles: [MarcRelator.trl], toLang: 'es'),
            Actor(name: 'Kaiser', roles: [MarcRelator.pfr]),
            Actor(name: 'Yen Press', roles: [MarcRelator.imageEditor]),
            Actor(name: 'Su-chan', roles: [MarcRelator.hnr], separated: true),
            Actor(name: 'Oculto', roles: [MarcRelator.ctb], credited: false),
            Actor(name: 'Zack', roles: [MarcRelator.mrk]),
            Actor(name: 'ZeePubs', roles: [MarcRelator.dst], url: 'https://www.facebook.com/ZeePubs'),
          ],
        ),
      ),
    );
    final title = files['OEBPS/Text/titulo.xhtml']!;
    expect(
      title,
      contains('''
      <p class="space-1"><b>Autor:</b> <ruby>鎌池 和馬<rp>(</rp><rt>Kamachi Kazuma</rt><rp>)</rp></ruby></p>
      <p><b>Ilustraciones:</b> Haimura Kiyotaka</p>
      <p class="space-1"><b>Traducción jap-ing:</b> js06</p>
      <p><b>Traducción al español:</b> Lestat</p>
      <p><b>Corrección:</b> Kaiser</p>
      <p><b>Edición de imágenes:</b> Yen Press</p>
      <p><b>Agradecimientos especiales:</b> Su-chan</p>
      <p class="space-1"><b>Epub:</b> Zack (<a href="https://www.facebook.com/ZeePubs">ZeePubs</a>)</p>
'''),
    );
    expect(title, isNot(contains('Oculto')));
    expect(title, contains('<h2 class="subtitle sigil_not_in_toc" role="doc-subtitle">Volumen 03<br/><small>[Novela ligera]</small></h2>'));
    // La edición de imágenes no tiene código MARC propio: en el OPF es un colaborador.
    final opf = files['OEBPS/content.opf']!;
    final yenPress = RegExp(r'<dc:contributor id="(\w+)">Yen Press</dc:contributor>').firstMatch(opf)!.group(1);
    expect(opf, contains('<meta refines="#$yenPress" property="role" scheme="marc:relators">ctb</meta>'));
  });

  test('varias personas con la misma función comparten línea: «A, B y C»', () {
    final lines = creditLines(const [
      Actor(name: 'Rin-san', roles: [MarcRelator.trl], toLang: 'es'),
      Actor(name: 'Edngo', roles: [MarcRelator.trl], toLang: 'es'),
      Actor(name: 'Kaiser', roles: [MarcRelator.trl], toLang: 'es'),
      Actor(name: 'Solo', roles: [MarcRelator.pfr]),
    ]);
    expect([for (final l in lines) (l.label, l.names)], [('Traducción al español', 'Rin-san, Edngo y Kaiser'), ('Corrección', 'Solo')]);
  });

  test('el título sigue a la serie mientras empiece por ella', () {
    expect(followSeries('', '', 'S'), 'S');
    expect(followSeries('Serie - Volumen 03 [GS]', 'Serie', 'Serie Nueva'), 'Serie Nueva - Volumen 03 [GS]');
    expect(followSeries('Otro título', 'Serie', 'Serie Nueva'), 'Otro título');
    expect(followSeriesAlternates(const [LocalizedText(lang: 'es', text: 'La serie - Volumen 03')], const [LocalizedText(lang: 'es', text: 'La serie')], const [LocalizedText(lang: 'es', text: 'La saga')]), const [LocalizedText(lang: 'es', text: 'La saga - Volumen 03')]);
  });

  test('la página de título separa el título y el subtítulo de la obra en líneas con su semántica', () {
    final sections = [TemplateSection.of(SectionKind.titlePage).copyWith(title: 'Mitsuba', subtitle: 'El inicio')];
    final title = _build(_project(sections: sections))['OEBPS/Text/titulo.xhtml']!;
    expect(title, contains('epub:type="fulltitle">\n      <span epub:type="title">Mitsuba</span><br/>\n      <span class="small" epub:type="subtitle">El inicio</span>\n    </h1>'));
    expect(RegExp(r'<h1[\s\S]*?</h1>').firstMatch(title)!.group(0), isNot(contains('<small>')));
  });

  test('las notas son una lista con tres de ejemplo enlazadas con sus llamadas en la primera sección de texto', () {
    final sections = [TemplateSection.of(SectionKind.cover), TemplateSection.of(SectionKind.chapter), TemplateSection.of(SectionKind.endnotes)];
    final files = _build(_project(sections: sections));
    final notes = files['OEBPS/Text/notas.xhtml']!;
    expect(notes, contains('<ol class="notes">'));
    expect(notes, contains('<li id="nt1"><p><a href="capitulo01.xhtml#rf1" role="doc-backlink"><sup>&#10094;01&#10095;</sup></a> Texto de la nota.</p></li>'));
    expect(notes, contains('id="nt3"'));
    expect(notes, isNot(contains('<aside')));
    expect(files['OEBPS/Text/capitulo01.xhtml'], contains('<a href="notas.xhtml#nt2" id="rf2" epub:type="noteref" role="doc-noteref"><sup>&#10094;02&#10095;</sup></a>'));
  });

  test('autor, editorial, fecha, demografía, géneros y serie son obligatorios', () {
    Iterable<String> issues(BookMetadata Function(BookMetadata m) edit) => templateIssues(_project(metadata: edit)).map((i) => i.message);
    expect(issues((m) => m.copyWith(actors: const [])), contains('El autor es obligatorio.'));
    expect(issues((m) => m.copyWith(publishers: const [''])), contains('La editorial es obligatoria.'));
    expect(issues((m) => m.copyWith(date: '')), contains('La fecha de publicación es obligatoria.'));
    expect(issues((m) => m.copyWith(demographic: null)), contains('La demografía es obligatoria.'));
    expect(issues((m) => m.copyWith(genres: const [])), contains('Elige al menos un género.'));
    expect(issues((m) => m.copyWith(series: '')), contains('La serie es obligatoria salvo en un volumen único.'));
    expect(issues((m) => m.copyWith(series: '', standalone: true)), isNot(contains('La serie es obligatoria salvo en un volumen único.')));
    expect(issues((m) => m.copyWith(altSeries: const [])), contains('La serie en español es obligatoria.'));
  });

  test('la sinopsis es obligatoria y el ISBN pegado con guiones se reordena', () {
    expect(templateIssues(_project(metadata: (m) => m.copyWith(description: ''))).map((i) => i.message), contains('La sinopsis es obligatoria.'));
    expect(templateIssues(_project(metadata: (m) => m.copyWith(description: 'Una historia.'))).map((i) => i.message), isNot(contains('La sinopsis es obligatoria.')));
    expect(formatIsbn('978-4-04-685088-1', isbn13Groups), '978-40-4685-088-1');
    expect(formatIsbn('4-04-685088-4', isbn10Groups), '40-4685-088-4');
  });

  test('el CSS propio va al final de style.css', () {
    final style = _build(_project().copyWith(customCss: '.carta {\n  font-style: italic;\n}\n'))['OEBPS/Styles/style.css']!;
    expect(style, endsWith('\n.carta {\n  font-style: italic;\n}\n'));
  });

  test('el título en español es obligatorio una vez escrito el principal', () {
    String? issue(TemplateProject p) => templateIssues(p).where((i) => i.message == 'El título en español es obligatorio.').firstOrNull?.message;
    expect(issue(_project()), isNull);
    expect(issue(_project(metadata: (m) => m.copyWith(altTitles: const []))), isNotNull);
    expect(
      issue(
        _project(
          metadata: (m) => m.copyWith(title: '', altTitles: const []),
        ),
      ),
      isNull,
    );
  });

  test('todos los documentos generados son XML bien formado', () {
    final files = _build(_project());
    for (final MapEntry(key: path, value: content) in files.entries) {
      if (path.endsWith('.xhtml') || path.endsWith('.opf') || path.endsWith('.xml')) {
        expect(() => XmlDocument.parse(content), returnsNormally, reason: path);
      }
    }
  });

  test('metadatos: roles, IDs secuenciales, alternate-script y temas', () {
    final opf = XmlDocument.parse(_build(_project())['OEBPS/content.opf']!);
    final metas = opf.findAllElements('meta');
    String? metaFor(String refines, String property) => metas.where((m) => m.getAttribute('refines') == '#$refines' && m.getAttribute('property') == property).firstOrNull?.innerText;

    expect(opf.findAllElements('dc:creator').map((e) => e.getAttribute('id')), ['creator01', 'creator02']);
    expect(opf.findAllElements('dc:contributor').map((e) => e.getAttribute('id')), ['contrib01', 'contrib02']);
    expect(metas.where((m) => m.getAttribute('refines') == '#contrib01' && m.getAttribute('property') == 'role').map((m) => m.innerText), ['trl', 'pfr']);
    expect(metaFor('creator01', 'alternate-script'), '七沢またり');

    final titleAlternates = metas.where((m) => m.getAttribute('refines') == '#title' && m.getAttribute('property') == 'alternate-script');
    expect(titleAlternates.map((m) => m.getAttribute('xml:lang')), ['es']);

    expect(opf.findAllElements('dc:subject').map((e) => e.innerText), ['Maduro', 'Adultos/Seinen', 'Acción', 'Fantasía']);
    expect(metaFor('serie', 'collection-type'), 'series');
    expect(metaFor('serie', 'group-position'), '3');
    expect(metas.where((m) => m.getAttribute('name') == 'calibre:series').single.getAttribute('content'), 'Mitsuba’s Stories [NL]');
    expect(opf.toXmlString(), isNot(contains('xsd:')));
  });

  test('un volumen único no escribe datos de serie', () {
    final files = _build(_project(metadata: (m) => m.copyWith(standalone: true)));
    expect(files['OEBPS/content.opf'], isNot(contains('belongs-to-collection')));
    expect(files['OEBPS/content.opf'], isNot(contains('calibre:series')));
    expect(files['OEBPS/Text/titulo.xhtml'], isNot(contains('Volumen')));
    expect(files['OEBPS/Text/titulo.xhtml'], contains('role="doc-subtitle"><small>[Novela ligera]</small></h2>'));
  });

  test('el índice anida los niveles y omite las secciones fuera de él', () {
    final sections = [
      TemplateSection.of(SectionKind.cover),
      TemplateSection.of(SectionKind.part),
      TemplateSection.of(SectionKind.chapter).copyWith(level: 2, subtitle: 'El inicio'),
      TemplateSection.of(SectionKind.chapter, number: 2).copyWith(level: 3),
      TemplateSection.of(SectionKind.epilogue),
      TemplateSection.of(SectionKind.endnotes),
    ];
    final nav = XmlDocument.parse(_build(_project(sections: sections))['OEBPS/Text/toc.xhtml']!);
    final toc = nav.findAllElements('nav').firstWhere((n) => n.getAttribute('epub:type') == 'toc');
    final topLevel = toc.getElement('ol')!.childElements.map((li) => li.getElement('a')!.innerText);
    expect(topLevel, ['Cubierta', 'Parte 1', 'Epílogo']);
    final nested = toc.findAllElements('li').firstWhere((li) => li.getElement('a')!.innerText == 'Parte 1').getElement('ol')!;
    expect(nested.findAllElements('a').map((a) => a.innerText), ['Capítulo 1: El inicio', 'Capítulo 2']);
    expect(toc.findAllElements('a').map((a) => a.innerText), isNot(contains('Notas')));

    final landmarks = nav.findAllElements('nav').firstWhere((n) => n.getAttribute('epub:type') == 'landmarks');
    expect(landmarks.findAllElements('a').map((a) => a.getAttribute('epub:type')), containsAllInOrder(['cover', 'bodymatter', 'epilogue', 'endnotes', 'toc']));
  });

  test('las secciones de imágenes generan un archivo por imagen y la cubierta marca cover-image', () {
    final sections = [
      TemplateSection.of(SectionKind.cover).copyWith(images: ['C:/img/portada final.png']),
      TemplateSection.of(SectionKind.illustrations).copyWith(images: ['C:/img/02.png', 'C:/img/03.png']),
      TemplateSection.of(SectionKind.colophon),
    ];
    final files = _build(
      _project(sections: sections),
      images: {
        for (final p in ['C:/img/portada final.png', 'C:/img/02.png', 'C:/img/03.png']) p: _png,
      },
    );
    expect(files.keys, containsAll(['OEBPS/Text/resumen.xhtml', 'OEBPS/Text/resumen_0001.xhtml', 'OEBPS/Images/cover.png', 'OEBPS/Images/02.png', 'OEBPS/Images/zeepubs.png']));
    final opf = files['OEBPS/content.opf']!;
    expect(opf, contains('<item id="cover.png" href="Images/cover.png" media-type="image/png" properties="cover-image"/>'));
    expect(opf, contains('<item id="x02.png"'));
    expect(files['OEBPS/Text/cubierta.xhtml'], contains('role="doc-cover"'));
  });

  test('accesibilidad: las ilustraciones hacen el contenido visual; la cubierta y los logos no', () {
    List<String> a11y(String opf) => [
      for (final m in XmlDocument.parse(opf).findAllElements('meta'))
        if ((m.getAttribute('property') ?? '').startsWith('schema:')) '${m.getAttribute('property')}=${m.innerText}',
    ];
    final cover = TemplateSection.of(SectionKind.cover).copyWith(images: ['C:/img/cover.png']);
    final images = {'C:/img/cover.png': _png, 'C:/img/02.png': _png};
    final plain = a11y(_build(_project(sections: [cover, TemplateSection.of(SectionKind.colophon)]), images: images)['OEBPS/content.opf']!);
    expect(plain, [
      'schema:accessMode=textual',
      'schema:accessModeSufficient=textual',
      'schema:accessibilityFeature=structuralNavigation',
      'schema:accessibilityFeature=tableOfContents',
      'schema:accessibilityFeature=readingOrder',
      'schema:accessibilityFeature=displayTransformability',
      'schema:accessibilityHazard=none',
    ]);
    final illustrated = a11y(
      _build(_project(sections: [cover, TemplateSection.of(SectionKind.illustrations).copyWith(images: ['C:/img/02.png'])]), images: images)['OEBPS/content.opf']!,
    );
    expect(illustrated, containsAllInOrder(['schema:accessMode=textual', 'schema:accessMode=visual', 'schema:accessModeSufficient=textual,visual']));
    expect(illustrated, isNot(contains('schema:accessModeSufficient=textual')));
    expect(illustrated.last, 'schema:accessibilitySummary=Las ilustraciones no tienen descripción alternativa.');
  });

  test('página separadora: el índice apunta a la imagen y el título visible abre el segundo archivo', () {
    final sections = [
      TemplateSection.of(SectionKind.chapter).copyWith(headingStyle: HeadingStyle.separatorPage, headingImage: 'C:/img/05.png', subtitle: 'Mi primer amigo'),
      TemplateSection.of(SectionKind.chapter, number: 2).copyWith(headingStyle: HeadingStyle.imageTitle, headingImage: 'C:/img/10.png'),
      TemplateSection.of(SectionKind.chapter, number: 3).copyWith(headingStyle: HeadingStyle.imageBefore, headingImage: 'C:/img/star.png'),
    ];
    final files = _build(
      _project(sections: sections),
      images: {
        for (final n in ['05', '10', 'star']) 'C:/img/$n.png': _png,
      },
    );

    final separator = XmlDocument.parse(files['OEBPS/Text/capitulo01.xhtml']!);
    final hidden = separator.findAllElements('h1').single;
    expect(hidden.getAttribute('class'), 'hidden');
    expect(hidden.getAttribute('title'), 'Capítulo 1: Mi primer amigo');
    expect(separator.findAllElements('figure').single.getAttribute('class'), 'fill');

    final text = XmlDocument.parse(files['OEBPS/Text/capitulo01_0001.xhtml']!);
    expect(text.findAllElements('h1').single.getAttribute('class'), 'sigil_not_in_toc');
    expect(text.findAllElements('section').single.getAttribute('role'), 'doc-chapter');

    final nav = files['OEBPS/Text/toc.xhtml']!;
    expect(nav, contains('<a href="capitulo01.xhtml">Capítulo 1: Mi primer amigo</a>'));
    expect(nav, isNot(contains('capitulo01_0001.xhtml')));

    final banner = XmlDocument.parse(files['OEBPS/Text/capitulo02.xhtml']!);
    expect(banner.findAllElements('img').single.getAttribute('alt'), 'Capítulo 2');
    expect(separator.findAllElements('img').single.getAttribute('alt'), 'Capítulo 1: Mi primer amigo');
    expect(banner.findAllElements('figure').single.getAttribute('class'), 'fill');

    final before = files['OEBPS/Text/capitulo03.xhtml']!;
    expect(before.indexOf('<figure class="logo">'), lessThan(before.indexOf('<h1')));
  });

  test('las fuentes incrustadas se declaran en el manifiesto y se aplican a sus niveles', () {
    final font = (
      font: const EmbeddedFont(family: 'Times New Roman', headingLevels: [1, 8]),
      files: <FontFile>[(path: 'C:/f/times.ttf', bytes: _png, weight: 400, italic: false), (path: 'C:/f/timesbd.ttf', bytes: _png, weight: 700, italic: false)],
    );
    final entries = EpubTemplateBuilder(
      project: _project(),
      styleCss: File('assets/epub_templater/style.css').readAsStringSync(),
      navCss: '',
      images: const {},
      fonts: [font],
    ).build();
    final files = {for (final e in entries) e.path: e};
    expect(files.keys, containsAll(['OEBPS/Fonts/times.ttf', 'OEBPS/Fonts/timesbd.ttf']));
    expect(utf8.decode(files['OEBPS/content.opf']!.bytes), contains('<item id="timesbd.ttf" href="Fonts/timesbd.ttf" media-type="font/ttf"/>'));
    final css = utf8.decode(files['OEBPS/Styles/style.css']!.bytes);
    expect(css, contains('font-weight: bold;\n  font-style: normal;\n  src: url(../Fonts/timesbd.ttf);'));
    expect(css, endsWith('h1,\nh1.title,\n.h8,\n.font-times-new-roman {\n  font-family: "Times New Roman", serif;\n}\n'));
  });

  test('el rol ARIA se deriva siempre del epub:type', () {
    final sections = [
      TemplateSection.of(SectionKind.chapter),
      TemplateSection.of(SectionKind.generic).copyWith(epubType: 'other-credits'),
      TemplateSection.of(SectionKind.titlePage),
    ];
    final files = _build(_project(sections: sections));
    expect(files['OEBPS/Text/capitulo01.xhtml'], contains('<section epub:type="chapter" role="doc-chapter"'));
    expect(files['OEBPS/Text/seccion.xhtml'], contains('<section epub:type="other-credits" role="doc-credits"'));
    expect(files['OEBPS/Text/titulo.xhtml'], contains('<section epub:type="titlepage" aria-labelledby'));
  });

  test('fileAsFor pone el apellido delante', () {
    expect(fileAsFor('Nanasawa Matari'), 'Matari, Nanasawa');
    expect(fileAsFor('  EURA '), 'EURA');
  });

  test('los comentarios de guía solo se escriben si están activados', () {
    final sections = [TemplateSection.of(SectionKind.chapter)];
    final without = _build(_project(sections: sections));
    expect(without['OEBPS/Text/capitulo01.xhtml'], isNot(contains('<!--')));
    expect(without['OEBPS/Styles/style.css'], isNot(contains('Niveles 7 a 9')));
    expect(without['OEBPS/Styles/style.css'], contains('/* Fin del CSS */'));

    final withGuide = _build(_project(sections: sections).copyWith(guideComments: true));
    expect(withGuide['OEBPS/Text/capitulo01.xhtml'], contains('<!-- ${SectionKind.chapter.purpose} -->'));
    expect(withGuide['OEBPS/Text/capitulo01.xhtml'], contains('<!-- Aquí va el contenido -->'));
    expect(withGuide['OEBPS/Styles/style.css'], contains('Niveles 7 a 9'));
  });

  test('templateIssues detecta archivos repetidos y título vacío', () {
    final sections = [TemplateSection.of(SectionKind.chapter), TemplateSection.of(SectionKind.chapter)];
    final issues = templateIssues(
      _project(
        metadata: (m) => m.copyWith(title: ' '),
        sections: sections,
      ),
    );
    expect(issues.where((i) => i.level == IssueLevel.error).map((i) => i.message), containsAll(['El título es obligatorio.', 'El archivo «capitulo01» está repetido.']));
  });

  test('una sección fuera del índice no lleva encabezado oculto: se nombra con aria-label', () {
    final files = _build(_project(sections: [TemplateSection.of(SectionKind.cover), TemplateSection.of(SectionKind.colophon), TemplateSection.of(SectionKind.backCover)]));
    for (final name in ['logos', 'contracubierta']) {
      final doc = files['OEBPS/Text/$name.xhtml']!;
      expect(doc, isNot(contains('<h1')), reason: name);
      expect(doc, contains('aria-label="'), reason: name);
    }
    expect(files['OEBPS/Text/cubierta.xhtml'], contains('<h1 id="encabezado" class="hidden">'));
  });

  test('la sinopsis separa párrafos por líneas en blanco y usa <br/> en los saltos simples', () {
    final files = _build(
      _project(
        metadata: (m) => m.copyWith(description: 'Uno\nDos\n\nTres <br> literal'),
        sections: [TemplateSection.of(SectionKind.synopsis)],
      ),
    );
    expect(files['OEBPS/Text/sinopsis.xhtml'], contains('<p>Uno<br/>Dos</p>'));
    expect(files['OEBPS/Text/sinopsis.xhtml'], contains('<p>Tres &lt;br&gt; literal</p>'));
  });

  test('la advertencia escribe el texto del tipo elegido', () {
    final files = _build(_project(sections: [TemplateSection.of(SectionKind.notice).copyWith(warning: ContentWarning.mature)]));
    expect(files['OEBPS/Text/advertencia.xhtml'], contains(ContentWarning.mature.text));
    expect(files['OEBPS/Text/advertencia.xhtml'], isNot(contains(ContentWarning.explicit.text)));
  });
}
