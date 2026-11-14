import 'package:flutter_test/flutter_test.dart';
import 'package:zeetools/features/epub_templater/data/epub_template_builder.dart';
import 'package:zeetools/features/epub_templater/data/opf_metadata.dart';
import 'package:zeetools/features/epub_templater/domain/book_metadata.dart';
import 'package:zeetools/features/epub_templater/domain/marc_relator.dart';
import 'package:zeetools/features/epub_templater/domain/metadata_field.dart';
import 'package:zeetools/features/epub_templater/domain/subjects.dart';
import 'package:zeetools/features/epub_templater/domain/title_languages.dart';

// Metadatos con la forma de la plantilla anterior: colección «set», urn:uri y prefijos xsd.
const _legacyOpf = '''<?xml version="1.0" encoding="utf-8"?>
<package version="3.0" unique-identifier="BookId" xml:lang="es" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:language>es</dc:language>
    <dc:title>86 - Volumen 01 [ShinsengumiTL]</dc:title>
    <dc:date>2017-02-10T00:00:00Z</dc:date>
    <dc:creator id="creator01">Asato Asato</dc:creator>
    <meta property="role" refines="#creator01" scheme="marc:relators">aut</meta>
    <meta property="alternate-script" refines="#creator01" xml:lang="ja">安里 アサト</meta>
    <meta property="file-as" refines="#creator01">Asato, Asato</meta>
    <dc:type>Novela Ligera</dc:type>
    <dc:subject>Maduro</dc:subject>
    <dc:subject>Adultos/Seinen</dc:subject>
    <dc:subject>Acción</dc:subject>
    <dc:subject>Mecha</dc:subject>
    <dc:description>Sinopsis.</dc:description>
    <dc:contributor id="contrib1">Meraru</dc:contributor>
    <meta property="role" refines="#contrib1" scheme="marc:relators">trl</meta>
    <dc:publisher>Shinsengumi Translations</dc:publisher>
    <dc:identifier id="BookId">urn:uuid:5eee6da9-9951-4726-84a9-38383b22d39d</dc:identifier>
    <dc:identifier id="isbn13">urn:isbn:978-19-7530-312-9</dc:identifier>
    <meta property="identifier-type" refines="#isbn13" scheme="onix:codelist5">15</meta>
    <dc:identifier id="amazon-id">urn:amazon:B08CPBD8PF</dc:identifier>
    <meta property="identifier-type" refines="#amazon-id" scheme="xsd:string">amazon</meta>
    <dc:identifier id="uri-id">urn:uri:https://example.com/86</dc:identifier>
    <meta property="identifier-type" refines="#uri-id" scheme="xsd:string">uri</meta>
    <meta id="serie" property="belongs-to-collection">86 - EIGHTY-SIX [NL]</meta>
    <meta property="collection-type" refines="#serie">set</meta>
    <meta property="group-position" refines="#serie">1</meta>
    <meta content="86 - EIGHTY-SIX [NL]" name="calibre:series"/>
    <meta content="1" name="calibre:series_index"/>
    <meta content="9" name="calibre:rating"/>
    <meta property="dcterms:modified">2022-10-25T16:37:08Z</meta>
    <meta content="1.9.20" name="Sigil version"/>
    <meta name="cover" content="cover.jpg"/>
  </metadata>
  <manifest/>
</package>
''';

void main() {
  test('lee los metadatos de la plantilla anterior', () {
    final m = OpfMetadata(_legacyOpf).read();
    expect(m.identifier, '5eee6da9-9951-4726-84a9-38383b22d39d');
    expect(m.title, '86 - Volumen 01 [ShinsengumiTL]');
    expect(m.date, '2017-02-10T00:00:00Z');
    expect(m.actors, [
      // Sin separadores guardados, una línea en blanco tras el último creador.
      const Actor(
        name: 'Asato Asato',
        fileAs: 'Asato, Asato',
        altNames: [LocalizedText(lang: 'ja', text: '安里 アサト')],
        roles: [MarcRelator.aut],
        separated: true,
      ),
      const Actor(name: 'Meraru', roles: [MarcRelator.trl]),
    ]);
    expect(m.demographic, Demographic.seinen);
    expect(m.genres, ['Acción']);
    expect(m.isbn13, '978-19-7530-312-9');
    expect(m.asin, 'B08CPBD8PF');
    expect(m.sourceUrl, 'https://example.com/86');
    // La etiqueta del tipo no se edita: se quita al leer y se añade al escribir.
    expect((m.series, m.seriesIndex, m.rating), ('86 - EIGHTY-SIX', '1', 9));
  });

  test('reescribe solo los metadatos editables y conserva el resto', () {
    final opf = OpfMetadata(_legacyOpf);
    final m = opf.read().copyWith(seriesIndex: '2');
    final written = opf.write(_legacyOpf, m, now: DateTime.utc(2026, 1, 2, 3, 4, 5));

    for (final kept in ['<dc:subject>Mecha</dc:subject>', 'name="Sigil version"', '<meta name="cover" content="cover.jpg"/>', '<manifest/>']) {
      expect(written, contains(kept));
    }
    expect(written, contains('<meta refines="#serie" property="collection-type">series</meta>'));
    expect(written, isNot(contains('coleccion')));

    // La colección acompaña a la serie sin ocupar su lugar, también al releer.
    final grouped = OpfMetadata(opf.write(_legacyOpf, m.copyWith(collection: '86'), now: DateTime.utc(2026)));
    final again = grouped.read();
    expect((again.series, again.seriesIndex, again.collection), ('86 - EIGHTY-SIX', '2', '86'));
    final rewritten = grouped.write(_legacyOpf, again.copyWith(standalone: true), now: DateTime.utc(2026));
    expect(rewritten, contains('<meta id="coleccion" property="belongs-to-collection">86</meta>\n    <meta refines="#coleccion" property="collection-type">set</meta>'));
    expect(OpfMetadata(rewritten).read().hasSeries, isFalse);
    expect(written, contains('<meta refines="#serie" property="group-position">2</meta>'));
    expect(written, contains('<dc:identifier id="uri-id">https://example.com/86</dc:identifier>'));
    expect(written, contains('2026-01-02T03:04:05Z'));
    for (final gone in ['>set<', 'xsd:string', '2022-10-25', 'contrib1']) {
      expect(written, isNot(contains(gone)));
    }
    expect(OpfMetadata(written).read(), m);
  });

  test('los campos que difieren entre libros se vacían y solo se aplican si se editan', () {
    const a = BookMetadata(title: 'Vol 1', series: 'S', seriesIndex: '1', genres: ['Acción']);
    const b = BookMetadata(title: 'Vol 2', series: 'S', seriesIndex: '2', genres: ['Acción']);
    final (:common, :mixed) = commonMetadata([a, b]);
    expect(mixed, {MetadataField.title, MetadataField.seriesIndex});
    expect((common.title, common.seriesIndex, common.series), ('', '', 'S'));

    final form = common.copyWith(series: 'Serie', genres: ['Drama']);
    final changed = changedFields(common, form);
    expect(changed, {MetadataField.series, MetadataField.genres});
    expect(applyFields(b, form, changed), b.copyWith(series: 'Serie', genres: ['Drama']));
  });

  test('la serie lleva la etiqueta del tipo y la novela web cambia ISBN y ASIN por su publicación original', () {
    final m = OpfMetadata(_legacyOpf).read();
    String written(BookMetadata edited) => OpfMetadata(_legacyOpf).write(_legacyOpf, edited, now: DateTime.utc(2026));
    expect(written(m.copyWith(bookType: 'Novela')), contains('<meta name="calibre:series" content="86 - EIGHTY-SIX [N]"/>'));
    final web = written(m.copyWith(bookType: 'Novela web', isbn13: '978-40-4685-088-1', asin: 'B00GD14MOA', originalSource: 'https://ncode.syosetu.com/n3009bk'));
    expect(web, contains('>86 - EIGHTY-SIX [NW]</meta>'));
    expect(web, contains('<dc:source>https://ncode.syosetu.com/n3009bk</dc:source>'));
    expect(web, isNot(contains('urn:isbn:')));
    expect(web, isNot(contains('urn:amazon:')));
    expect(OpfMetadata(web).read().originalSource, 'https://ncode.syosetu.com/n3009bk');
    expect(m.copyWith(bookType: 'Novela').amazonStore, AmazonStore.com);
    expect(m.amazonStore, AmazonStore.jp);
  });

  test('el traductor a otro idioma que el del libro no va al OPF, solo a los créditos', () {
    final m = OpfMetadata(_legacyOpf).read().copyWith(actors: const [
      Actor(name: 'Asato Asato', roles: [MarcRelator.aut]),
      Actor(name: 'J-Novel Club', roles: [MarcRelator.trl], fromLang: 'ja', toLang: 'en', credited: false),
      Actor(name: 'Mark', roles: [MarcRelator.trl, MarcRelator.pfr], toLang: 'es'),
      Actor(name: 'Sin destino', roles: [MarcRelator.trl]),
    ]);
    final written = OpfMetadata(_legacyOpf).write(_legacyOpf, m, now: DateTime.utc(2026));
    expect(written, isNot(contains('J-Novel Club')));
    expect(written, contains('>Mark</dc:contributor>'));
    expect(written, contains('>Sin destino</dc:contributor>'));
    expect([for (final l in creditLines(m.actors, bookLanguage: 'es')) l.names], ['Asato Asato', 'J-Novel Club', 'Mark', 'Sin destino']);
  });

  test('descarta la fecha indefinida de calibre', () {
    final opf = _legacyOpf.replaceFirst('2017-02-10T00:00:00Z', '0101-01-01T00:00:00+00:00');
    expect(OpfMetadata(opf).read().date, isEmpty);
  });

  test('la descripción guarda los saltos como <br> y un <br> escrito a mano como texto', () {
    const text = 'Primera línea\nSegunda <br> escrita & más';
    expect(descriptionToHtml(text), 'Primera línea<br/>Segunda &lt;br&gt; escrita &amp; más');
    expect(descriptionFromHtml(descriptionToHtml(text)), text);
    expect(descriptionFromHtml('<p>Uno</p><p>Dos<br/>tres</p>'), 'Uno\n\nDos\ntres');
    expect(descriptionFromHtml('La <Familia Hestia> y <b>Bell</b><br/>fin'), 'La <Familia Hestia> y Bell\nfin');

    final opf = OpfMetadata(_legacyOpf);
    final m = opf.read().copyWith(description: text);
    final written = opf.write(_legacyOpf, m, now: DateTime.utc(2026));
    expect(written, contains('<dc:description>Primera línea&lt;br/&gt;Segunda &amp;lt;br&amp;gt; escrita &amp;amp; más</dc:description>'));
    expect(OpfMetadata(written).read().description, text);
  });

  test('tipo y temas del catálogo se leen sin distinguir mayúsculas y se escriben con mayúscula inicial', () {
    final opf = _legacyOpf.replaceFirst('<dc:subject>Mecha</dc:subject>', '<dc:subject>Sin Censura</dc:subject>\n    <dc:subject>Mecha</dc:subject>');
    final m = OpfMetadata(opf).read();
    expect(m.bookType, 'Novela ligera');
    expect(m.editions, ['Sin censura']);

    final written = OpfMetadata(opf).write(opf, m.copyWith(editions: ['Sin censura', 'A color']), now: DateTime.utc(2026));
    expect(written, contains('<dc:type>Novela ligera</dc:type>'));
    expect(written, contains('<dc:subject>Acción</dc:subject>\n    <dc:subject>A color</dc:subject>\n    <dc:subject>Sin censura</dc:subject>'));
    expect(written, isNot(contains('Sin Censura')));
    expect(written, contains('<dc:subject>Mecha</dc:subject>'));
  });

  test('el título en inglés pasa a principal y el que estaba queda como equivalente', () {
    final opf = _legacyOpf.replaceFirst(
      '<dc:title>86 - Volumen 01 [ShinsengumiTL]</dc:title>',
      '''<dc:title id="title">86 - Volumen 01 [ShinsengumiTL]</dc:title>
    <meta refines="#title" property="alternate-script" xml:lang="en">86 - Volume 01 [ShinsengumiTL]</meta>
    <meta refines="#title" property="alternate-script" xml:lang="ja">８６―エイティシックス―</meta>''',
    );
    final m = OpfMetadata(opf).read();
    expect((m.title, m.titleLang), ('86 - Volume 01 [ShinsengumiTL]', 'en'));
    expect(m.altTitles, const [LocalizedText(lang: 'es', text: '86 - Volumen 01 [ShinsengumiTL]'), LocalizedText(lang: 'ja', text: '８６―エイティシックス―')]);
    expect(OpfMetadata(opf).write(opf, m, now: DateTime.utc(2026)), contains('<dc:title id="title" xml:lang="en">86 - Volume 01 [ShinsengumiTL]</dc:title>'));
  });

  test('el idioma del libro, salvo el inglés del principal, es el equivalente obligatorio', () {
    expect((requiredAlternate('es'), requiredAlternate('en'), requiredAlternate('ja')), ('es', null, 'ja'));
    const items = [LocalizedText(lang: 'es', text: 'Bruja errante')];
    expect((missingRequired(items, 'es'), missingRequired(items, 'en'), missingRequired(items, 'ja')), (false, false, true));
    expect(languageName('ja'), 'japonés');
    final original = withOriginalLanguage(items, OriginalLanguage.ja);
    expect([for (final t in original) t.lang], ['es', 'ja-Latn', 'ja']);
    expect(withOriginalLanguage(original, null), items);
  });
}
