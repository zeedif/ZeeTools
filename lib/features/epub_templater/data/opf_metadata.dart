import 'package:xml/xml.dart';

import '/common/utils/uuid_v7.dart';
import '../domain/book_metadata.dart';
import '../domain/marc_relator.dart';
import '../domain/subjects.dart';
import '../domain/title_languages.dart';

const _dcNs = 'http://purl.org/dc/elements/1.1/';
const _opfNs = 'http://www.idpf.org/2007/opf';

String xmlEscape(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

// dc:description es HTML guardado como texto (así lo lee calibre): el texto se escapa y cada salto
// de línea pasa a <br/>, válido tanto si el lector lo trata como HTML como si lo inserta en XHTML;
// un «<br>» escrito a mano sigue siendo texto.
String descriptionToHtml(String text) => text
    .trim()
    .replaceAll('\r\n', '\n')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('\n', '<br/>');

const _entities = {'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': '\u00a0'};

// Etiquetas de HTML que se quitan al leer; cualquier otra cosa entre «<» y «>» (como «<Familia Hestia>»)
// es texto de la sinopsis.
final _htmlTag = RegExp(r'</?(p|div|span|b|i|em|strong|u|s|small|big|sup|sub|pre|blockquote|ul|ol|li|table|tbody|thead|tr|td|th|a|font|center)(\s[^>]*)?/?>', caseSensitive: false);

// Inversa de [descriptionToHtml]; también entiende los párrafos <p> de otros editores.
String descriptionFromHtml(String html) => html
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'</p>\s*<p[^>]*>', caseSensitive: false), '\n\n')
    .replaceAll(_htmlTag, '')
    .replaceAllMapped(RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);'), (m) {
      final ref = m.group(1)!;
      if (ref.startsWith('#x') || ref.startsWith('#X')) return String.fromCharCode(int.parse(ref.substring(2), radix: 16));
      if (ref.startsWith('#')) return String.fromCharCode(int.parse(ref.substring(1)));
      return _entities[ref] ?? m.group(0)!;
    })
    .trim();

final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);

// Elementos del bloque <metadata> que se derivan de [BookMetadata]; el
// identificador principal lleva el id BookId.
void writeOpfMetadata(StringBuffer b, BookMetadata m, {required DateTime now}) {
  final lang = m.language.trim();
  void meta(String property, String value, {String? refines, String? scheme, String? lang, String? id}) {
    final attrs = [
      if (id != null) 'id="$id"',
      if (refines != null) 'refines="#$refines"',
      'property="$property"',
      if (scheme != null) 'scheme="$scheme"',
      if (lang != null) 'xml:lang="${xmlEscape(lang)}"',
    ].join(' ');
    b.writeln('    <meta $attrs>${xmlEscape(value)}</meta>');
  }

  // alternate-script no puede compartir idioma con la propiedad que refina.
  void alternates(String refines, String ownLang, List<LocalizedText> texts) {
    for (final t in texts) {
      final altLang = t.lang.trim();
      if (altLang.isEmpty || t.text.trim().isEmpty || altLang.toLowerCase() == ownLang.toLowerCase()) continue;
      meta('alternate-script', t.text.trim(), refines: refines, lang: altLang);
    }
  }

  String langAttr(String value) => value.isEmpty || value == lang ? '' : ' xml:lang="${xmlEscape(value)}"';

  final identifier = m.identifier.trim().isEmpty ? uuidV7(now) : m.identifier.trim();
  b.writeln('    <dc:identifier id="BookId">${_uuid.hasMatch(identifier) ? 'urn:uuid:' : ''}${xmlEscape(identifier)}</dc:identifier>');

  final titleLang = m.titleLang.trim();
  b.writeln('    <dc:title id="title"${langAttr(titleLang)}>${xmlEscape(m.title.trim())}</dc:title>');
  meta('title-type', 'main', refines: 'title');
  if (m.titleSort.trim().isNotEmpty) meta('file-as', m.titleSort.trim(), refines: 'title');
  alternates('title', titleLang.isEmpty ? lang : titleLang, m.altTitles);

  b.writeln('    <dc:language>${xmlEscape(lang)}</dc:language>');
  if (m.date.trim().isNotEmpty) b.writeln('    <dc:date>${xmlEscape(m.date.trim())}</dc:date>');

  final people = m.actors.where((a) => a.name.trim().isNotEmpty && a.opfRoles(lang).isNotEmpty);
  for (final (creator, element, prefix) in const [(true, 'dc:creator', 'creator'), (false, 'dc:contributor', 'contrib')]) {
    for (final (i, actor) in people.where((a) => a.isCreator == creator).indexed) {
      final id = '$prefix${(i + 1).toString().padLeft(2, '0')}';
      b.writeln('    <$element id="$id">${xmlEscape(actor.name.trim())}</$element>');
      for (final code in {for (final role in actor.opfRoles(lang)) role.code}) {
        meta('role', code, refines: id, scheme: 'marc:relators');
      }
      if (actor.fileAs.trim().isNotEmpty) meta('file-as', actor.fileAs.trim(), refines: id);
      alternates(id, lang, actor.altNames);
    }
  }

  if (m.bookType.trim().isNotEmpty) b.writeln('    <dc:type>${xmlEscape(m.bookType.trim())}</dc:type>');
  for (final subject in m.subjects) {
    b.writeln('    <dc:subject>${xmlEscape(subject)}</dc:subject>');
  }
  if (m.description.trim().isNotEmpty) b.writeln('    <dc:description>${xmlEscape(descriptionToHtml(m.description))}</dc:description>');
  for (final (i, publisher) in m.publishers.where((x) => x.trim().isNotEmpty).indexed) {
    b.writeln('    <dc:publisher id="publisher${(i + 1).toString().padLeft(2, '0')}">${xmlEscape(publisher.trim())}</dc:publisher>');
  }

  // ONIX code list 5: 15 = ISBN-13, 02 = ISBN-10. Una novela web no tiene ISBN ni ASIN.
  final web = m.isWebNovel;
  if (!web && m.isbn13.trim().isNotEmpty) {
    b.writeln('    <dc:identifier id="isbn13">urn:isbn:${xmlEscape(m.isbn13.trim())}</dc:identifier>');
    meta('identifier-type', '15', refines: 'isbn13', scheme: 'onix:codelist5');
  }
  if (!web && m.isbn10.trim().isNotEmpty) {
    b.writeln('    <dc:identifier id="isbn10">urn:isbn:${xmlEscape(m.isbn10.trim())}</dc:identifier>');
    meta('identifier-type', '02', refines: 'isbn10', scheme: 'onix:codelist5');
  }
  if (!web && m.asin.trim().isNotEmpty) {
    b.writeln('    <dc:identifier id="amazon-id">urn:amazon:${xmlEscape(m.asin.trim())}</dc:identifier>');
    meta('identifier-type', 'amazon', refines: 'amazon-id');
  }
  if (m.sourceUrl.trim().isNotEmpty) {
    b.writeln('    <dc:identifier id="uri-id">${xmlEscape(m.sourceUrl.trim())}</dc:identifier>');
    meta('identifier-type', 'uri', refines: 'uri-id');
  }
  if (m.originalSource.trim().isNotEmpty) b.writeln('    <dc:source>${xmlEscape(m.originalSource.trim())}</dc:source>');

  if (m.hasSeries) {
    final seriesLang = m.seriesLang.trim();
    final index = m.seriesIndex.trim().isEmpty ? '1' : m.seriesIndex.trim();
    final series = taggedSeries(m.series, m.bookType);
    b.writeln('    <meta id="serie" property="belongs-to-collection"${langAttr(seriesLang)}>${xmlEscape(series)}</meta>');
    meta('collection-type', 'series', refines: 'serie');
    meta('group-position', index, refines: 'serie');
    alternates('serie', seriesLang.isEmpty ? lang : seriesLang, m.altSeries);
    // Metadatos OPF 2 que leen calibre y lectores sin soporte de colecciones EPUB 3.
    b
      ..writeln('    <meta name="calibre:series" content="${xmlEscape(series)}"/>')
      ..writeln('    <meta name="calibre:series_index" content="${xmlEscape(index)}"/>');
  }
  if (m.rating != null) b.writeln('    <meta name="calibre:rating" content="${m.rating}"/>');

  meta('dcterms:modified', '${now.toIso8601String().substring(0, 19)}Z');
}

// Metadatos de accesibilidad (EPUB Accessibility 1.1). Las imágenes no llevan texto alternativo, así que con
// ilustraciones el libro solo se lee completo con texto e imágenes; el resumen dice lo que los demás no expresan.
void writeAccessibilityMetadata(StringBuffer b, {required bool illustrated}) {
  void meta(String property, String value) => b.writeln('    <meta property="$property">$value</meta>');
  final modes = ['textual', if (illustrated) 'visual'];
  for (final mode in modes) {
    meta('schema:accessMode', mode);
  }
  meta('schema:accessModeSufficient', modes.join(','));
  for (final feature in const ['structuralNavigation', 'tableOfContents', 'readingOrder', 'displayTransformability']) {
    meta('schema:accessibilityFeature', feature);
  }
  meta('schema:accessibilityHazard', 'none');
  if (illustrated) meta('schema:accessibilitySummary', 'Las ilustraciones no tienen descripción alternativa.');
}

final _knownSubjects = {
  ...literaryGenres,
  ...editionFeatures,
  for (final d in Demographic.values) ...[d.label, d.ageGroup],
};

const _ownedDc = {'title', 'language', 'date', 'creator', 'contributor', 'type', 'description', 'publisher', 'source'};
const _ownedCalibre = {'calibre:series', 'calibre:series_index', 'calibre:rating', 'calibre:title_sort'};

// Lectura del OPF: los metadatos que entiende el formulario y los elementos
// que se reemplazan al escribirlos de nuevo.
class OpfMetadata {
  OpfMetadata(String opf) : _document = XmlDocument.parse(opf) {
    _metadata = _document.rootElement.childElements.firstWhere((e) => e.name.local == 'metadata');
    _uniqueId = _document.rootElement.getAttribute('unique-identifier') ?? '';
    for (final e in _metadata.childElements) {
      if (e.name.local != 'meta') continue;
      final target = e.getAttribute('refines')?.replaceFirst('#', '');
      if (target != null) _refines.putIfAbsent(target, () => []).add(e);
    }
  }

  final XmlDocument _document;
  late final XmlElement _metadata;
  late final String _uniqueId;
  final Map<String, List<XmlElement>> _refines = {};

  Iterable<XmlElement> _dc(String name) => _metadata.childElements.where((e) => e.name.namespaceUri == _dcNs && e.name.local == name);

  Iterable<XmlElement> _refinements(XmlElement e, String property) => _refines[e.getAttribute('id')] == null ? const [] : _refines[e.getAttribute('id')]!.where((r) => r.getAttribute('property') == property);

  String? _refined(XmlElement e, String property) => _refinements(e, property).firstOrNull?.innerText.trim();

  String _lang(XmlElement e) => (e.getAttribute('xml:lang') ?? '').trim();

  String? _named(String name) => _metadata.childElements.where((e) => e.name.local == 'meta' && e.getAttribute('name') == name).firstOrNull?.getAttribute('content')?.trim();

  List<LocalizedText> _alternates(XmlElement e) => [for (final r in _refinements(e, 'alternate-script')) LocalizedText(lang: _lang(r), text: r.innerText.trim())];

  // Qué representa cada dc:identifier, o null si no se edita en el formulario.
  ({String field, String value})? _identifier(XmlElement e) {
    final text = e.innerText.trim();
    final lower = text.toLowerCase();
    final scheme = (e.getAttribute('scheme', namespaceUri: _opfNs) ?? '').toLowerCase();
    if (e.getAttribute('id') == _uniqueId) return (field: 'identifier', value: lower.startsWith('urn:uuid:') ? text.substring(9) : text);
    if (lower.startsWith('urn:isbn:') || scheme == 'isbn') {
      final isbn = text.replaceFirst(RegExp('^urn:isbn:', caseSensitive: false), '');
      return (field: isbn.replaceAll(RegExp(r'[^0-9Xx]'), '').length == 10 ? 'isbn10' : 'isbn13', value: isbn);
    }
    if (lower.startsWith('urn:amazon:') || scheme == 'amazon' || scheme == 'mobi-asin' || scheme == 'asin') {
      return (field: 'asin', value: text.replaceFirst(RegExp('^urn:amazon:', caseSensitive: false), ''));
    }
    final url = text.replaceFirst(RegExp('^urn:uri:', caseSensitive: false), '');
    if (url.startsWith(RegExp('https?://', caseSensitive: false))) return (field: 'sourceUrl', value: url);
    return null;
  }

  XmlElement? get _seriesCollection => _metadata.childElements.where((e) {
    if (e.name.local != 'meta' || e.getAttribute('property') != 'belongs-to-collection') return false;
    // Versiones anteriores de la plantilla marcaban la serie como «set».
    final type = _refined(e, 'collection-type');
    return type == null || type == 'series' || type == 'set';
  }).firstOrNull;

  BookMetadata read() {
    final language = _dc('language').firstOrNull?.innerText.trim() ?? '';
    final titles = _dc('title').toList();
    final title = titles.where((t) => _refined(t, 'title-type') == 'main').firstOrNull ?? titles.firstOrNull;
    final identifiers = <String, String>{};
    for (final e in _dc('identifier')) {
      if (_identifier(e) case (:final field, :final value)) identifiers.putIfAbsent(field, () => value);
    }
    final subjects = [for (final e in _dc('subject')) catalogValue(_knownSubjects, e.innerText) ?? e.innerText.trim()];
    final collection = _seriesCollection;
    final rating = double.tryParse(_named('calibre:rating') ?? '');

    List<Actor> actors(String element, MarcRelator fallback) => [
      for (final e in _dc(element))
        Actor(
          name: e.innerText.trim(),
          fileAs: _refined(e, 'file-as') ?? e.getAttribute('file-as', namespaceUri: _opfNs)?.trim() ?? '',
          altNames: _alternates(e),
          roles: switch ({
            for (final code in [..._refinements(e, 'role').map((r) => r.innerText.trim()), ?e.getAttribute('role', namespaceUri: _opfNs)?.trim()]) ?MarcRelator.values.where((r) => r.name == code).firstOrNull,
          }.toList()) {
            final roles when roles.isNotEmpty => roles,
            _ => [fallback],
          },
        ),
    ];

    String langOf(XmlElement? e) => switch (e == null ? '' : _lang(e)) {
      '' => language,
      final lang => lang,
    };
    final mainTitle = mainFirst(title?.innerText.trim() ?? '', langOf(title), title == null ? const [] : _alternates(title));
    final series = mainFirst(collection?.innerText.trim() ?? _named('calibre:series') ?? '', langOf(collection), collection == null ? const [] : _alternates(collection));
    return BookMetadata(
      identifier: identifiers['identifier'] ?? '',
      language: language,
      title: mainTitle.text,
      titleLang: mainTitle.lang,
      titleSort: (title == null ? null : _refined(title, 'file-as')) ?? _named('calibre:title_sort') ?? '',
      altTitles: mainTitle.alternates,
      // calibre escribe 0101-01-01 cuando no hay fecha.
      date: switch (_dc('date').firstOrNull?.innerText.trim() ?? '') {
        final date when date.startsWith('0101-01-01') => '',
        final date => date,
      },
      bookType: switch (_dc('type').firstOrNull?.innerText.trim() ?? '') {
        final type => catalogValue(bookTypes, type) ?? type,
      },
      description: descriptionFromHtml(_dc('description').firstOrNull?.innerText ?? ''),
      actors: withDefaultSeparators([...actors('creator', MarcRelator.aut), ...actors('contributor', MarcRelator.ctb)]),
      publishers: [for (final e in _dc('publisher')) e.innerText.trim()],
      isbn13: identifiers['isbn13'] ?? '',
      isbn10: identifiers['isbn10'] ?? '',
      asin: identifiers['asin'] ?? '',
      sourceUrl: identifiers['sourceUrl'] ?? '',
      originalSource: _dc('source').firstOrNull?.innerText.trim() ?? '',
      // La etiqueta del tipo ([NL]…) se añade al escribir según el tipo de libro.
      series: seriesWithoutTag(series.text),
      seriesLang: series.lang,
      altSeries: series.alternates,
      seriesIndex: (collection == null ? null : _refined(collection, 'group-position')) ?? _named('calibre:series_index') ?? '1',
      standalone: series.text.trim().isEmpty,
      originalLanguage: originalLanguageOf(mainTitle.alternates) ?? originalLanguageOf(series.alternates),
      demographic: Demographic.values.where((d) => subjects.contains(d.label)).firstOrNull,
      genres: literaryGenres.where(subjects.contains).toList(),
      editions: editionFeatures.where(subjects.contains).toList(),
      rating: rating?.round(),
    );
  }

  bool _owned(XmlElement e, Set<String> ownedIds) {
    if (e.name.namespaceUri == _dcNs) {
      return switch (e.name.local) {
        final name when _ownedDc.contains(name) => true,
        'subject' => catalogValue(_knownSubjects, e.innerText) != null,
        'identifier' => _identifier(e) != null,
        _ => false,
      };
    }
    if (e.name.local != 'meta') return false;
    if (_ownedCalibre.contains(e.getAttribute('name'))) return true;
    if (e.getAttribute('property') == 'dcterms:modified' || e == _seriesCollection) return true;
    return ownedIds.contains(e.getAttribute('refines')?.replaceFirst('#', ''));
  }

  // OPF con el bloque de metadatos reescrito a partir de [m]; se conservan los
  // elementos que el formulario no edita, como la cubierta o la accesibilidad.
  String write(String opf, BookMetadata m, {DateTime? now}) {
    final elements = _metadata.childElements.toList();
    final ownedIds = {
      for (final e in elements)
        if (e.getAttribute('id') case final id? when e.getAttribute('refines') == null && _owned(e, const {})) id,
    };
    final b = StringBuffer('\n');
    writeOpfMetadata(b, m, now: (now ?? DateTime.now()).toUtc());
    for (final e in elements) {
      if (!_owned(e, ownedIds)) b.writeln('    ${e.toXmlString()}');
    }
    return opf.replaceFirstMapped(RegExp(r'(<(?:\w+:)?metadata\b[^>]*>)[\s\S]*?(</(?:\w+:)?metadata>)'), (match) => '${match[1]}$b  ${match[2]}').replaceFirst(RegExp(r'''unique-identifier\s*=\s*(["'])[^"']*\1'''), 'unique-identifier="BookId"');
  }
}
