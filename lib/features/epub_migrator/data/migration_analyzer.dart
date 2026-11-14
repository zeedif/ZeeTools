import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '/common/utils/input_formatters.dart';
import '/features/epub_templater/data/epub_template_builder.dart';
import '/features/epub_templater/data/opf_metadata.dart';
import '/features/epub_templater/domain/book_metadata.dart';
import '/features/epub_templater/domain/content_warning.dart';
import '/features/epub_templater/domain/section_kind.dart';
import '/features/epub_templater/domain/title_languages.dart';
import '../domain/migration_kind.dart';
import '../domain/migration_project.dart';
import 'css_rules.dart';
import 'epub_archive.dart';
import 'legacy_styles.dart';
import 'xhtml_utils.dart';

// Clases de texto del template anterior y su equivalente.
const textClassMap = {
  'amplio': ['transition'],
  'aviso': ['warning'],
  'borde': ['boxed'],
  'centrado': ['align-center'],
  'derecha': ['align-right'],
  'izquierda': ['align-left'],
  'justificado': ['justified'],
  'grande': ['large'],
  'identar': ['indent'],
  'noidentar': ['no-indent'],
  'no-identar': ['no-indent'],
  'idt-ln': ['hanging-indent'],
  'listar': ['list-indent'],
  'no-list': ['no-list-type'],
  'no-silabear': ['no-hyphens'],
  'nosepag': ['no-break-inside'],
  'noseparar': ['keep-together'],
  'nota': ['note'],
  'oculto': ['hidden'],
  'salto0': ['space-0'],
  'salto1': ['space-1'],
  'salto2': ['space-2'],
  'salto3': ['space-3'],
  'santes': ['break-before'],
  'ssigue': ['break-after'],
  'saltop': ['break-before'],
  'separador': ['break-before', 'break-after'],
  'sinmargen': ['no-margin'],
  'tabla-fija': ['table-fixed'],
  'titulo': ['title'],
  'subtitulo': ['subtitle'],
  'versalita': ['small'],
};

// Clases de imagen: su papel sale de las medidas de su regla; el nombre solo decide si no las tiene.
const _imageDefaults = {'dimg': 'fill', 'banner': 'fill', 'hr': 'text', 'entexto': 'text', 'logo': 'logo', 'icono': 'icon', 'separadorimg': 'text', 'vertical': '', 'imgtitulo': ''};
const _sigilClasses = {'sigil_not_in_toc', 'sigil_split_marker'};
const _genericFamilies = {'serif', 'sans-serif', 'monospace', 'cursive', 'fantasy', 'system-ui'};
// Hojas del índice que sustituye nav-style.css.
final _navSheets = RegExp(r'^(nav-style|toc-style|toc)\.css$', caseSensitive: false);

// Nombre de la fuente en Fonts/, con la extensión en minúsculas.
String fontFileName(String path) => '${p.posix.basenameWithoutExtension(path)}${p.posix.extension(path).toLowerCase()}';

String fontClass(String family) {
  final slug = family.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return 'font-${slug.isEmpty ? 'custom' : slug}';
}

class _Doc {
  _Doc(this.path, this.doc);

  final String path;
  final XmlDocument? doc;
  List<String> oldTypes = const [];
  List<XmlElement> headings = const [];
  MigrationKind kind = MigrationKind.generic;
  BookMatter matter = BookMatter.body;
  bool continuation = false;
  String label = '';
  bool inToc = true;
  final notes = <String>[];

  String get stem => p.posix.basenameWithoutExtension(path);

  List<XmlElement> get visible => [
    for (final h in headings)
      if (headingLabel(h).isNotEmpty || (h.getAttribute('title') ?? '').isNotEmpty) h,
  ];

  Iterable<XmlElement> get paragraphs => doc == null ? const [] : elementsOf(doc!, 'p').where((e) => textOf(e).isNotEmpty);

  List<XmlElement> get images => doc == null ? const [] : elementsOf(doc!, 'img').toList();
}

// Propuesta de migración de un EPUB con el template anterior: lo que se puede deducir
// del libro queda rellenado; lo dudoso, anotado para revisarlo.
MigrationProject analyzeEpub(String sourcePath, EpubArchive archive, {required String templateCss, LegacyTemplates? oldTemplates}) {
  final readIssues = <MigrationIssue>[];
  final oldNav = _oldNav(archive);
  final docs = [
    for (final item in archive.spineItems)
      if (item.id != archive.nav?.id && item.mediaType == 'application/xhtml+xml') _parse(archive, item.path, readIssues),
  ];
  _classify(docs, oldNav);
  _assignMatter(docs);
  final names = _standardNames(docs);

  final cssPaths = [
    for (final i in archive.manifest)
      if (i.mediaType == 'text/css' && archive.files.containsKey(i.path)) i.path,
  ];
  final used = <String>{
    for (final d in docs)
      if (d.doc != null)
        for (final e in d.doc!.descendants.whereType<XmlElement>()) ...classesOf(e),
  };
  final templateClasses = {...parseCss(templateCss).expand((r) => selectorsOf(r.prelude)).expand(classNames), ..._sigilClasses};
  final styles = _styles(archive, cssPaths, used, templateClasses, templateCss, oldTemplates);

  for (final d in docs) {
    for (final img in d.images) {
      if (isExternal(img.getAttribute('src') ?? '')) readIssues.add((level: MigrationIssueLevel.warning, message: 'Imagen enlazada desde internet: ${img.getAttribute('src')}', path: d.path));
    }
    final inline = d.doc == null ? 0 : d.doc!.descendants.whereType<XmlElement>().where((e) => (e.getAttribute('style') ?? '').isNotEmpty).length;
    if (inline > 0) readIssues.add((level: MigrationIssueLevel.warning, message: '$inline elemento${inline == 1 ? '' : 's'} con estilo en línea (style=…).', path: d.path));
    for (final e in d.doc?.descendants.whereType<XmlElement>() ?? const <XmlElement>[]) {
      for (final attr in const ['href', 'src']) {
        final value = e.getAttribute(attr) ?? '';
        if (value.isEmpty || value.startsWith('#') || isExternal(value)) continue;
        if (!archive.files.containsKey(resolvePath(d.path, value))) readIssues.add((level: MigrationIssueLevel.warning, message: 'Enlace roto: $value', path: d.path));
      }
    }
  }
  for (final i in archive.manifest) {
    final bytes = archive.files[i.path];
    if (!i.mediaType.startsWith('image/') || i.mediaType == 'image/svg+xml' || bytes == null) continue;
    final type = imageTypeOf(bytes);
    if (type == null) {
      readIssues.add((level: MigrationIssueLevel.warning, message: 'Imagen dañada o en un formato que no se reconoce.', path: i.path));
    } else if (type != i.mediaType) {
      readIssues.add((level: MigrationIssueLevel.info, message: 'Es $type aunque se declara ${i.mediaType}; se corrige en el OPF.', path: i.path));
    }
  }
  if (RegExp(r'\d\s*vh\b').hasMatch(styles.customCss)) readIssues.add((level: MigrationIssueLevel.warning, message: 'El CSS propio usa vh: los lectores no coinciden en qué mide.', path: null));
  if (archive.ncx != null) readIssues.add((level: MigrationIssueLevel.info, message: 'El NCX se elimina; el índice nuevo es toc.xhtml.', path: archive.ncx!.path));

  final notice = docs.where((d) => d.kind == MigrationKind.notice).firstOrNull;
  return MigrationProject(
    sourcePath: sourcePath,
    metadata: _metadata(archive),
    docs: [
      for (final (i, d) in docs.indexed) MigrationDoc(path: d.path, kind: d.kind, matter: d.matter, label: d.label, inToc: d.inToc, continuation: d.continuation, fileName: names[i], notes: d.notes, oldType: d.oldTypes.join(' '), headingText: d.visible.isEmpty ? '' : tocLabel(d.visible.first), paragraphs: d.paragraphs.length, images: d.images.length, broken: d.doc == null),
    ],
    classRenames: styles.renames,
    unknownClasses: styles.unknown,
    customCss: styles.customCss,
    replacedSheets: styles.sheets,
    warning: notice?.doc == null ? ContentWarning.explicit : contentWarningOf(textOf(notice!.doc!)) ?? ContentWarning.explicit,
    addLogos: !docs.any((d) => d.kind == MigrationKind.colophon),
    readIssues: readIssues,
  );
}

ContentWarning? contentWarningOf(String text) {
  final t = text.toLowerCase();
  if (t.contains('inteligencia artificial')) return ContentWarning.aiTranslation;
  if (t.contains('maduro')) return ContentWarning.mature;
  if (RegExp(r'depresi[oó]n|suicidio|bullying').hasMatch(t)) return ContentWarning.sensitive;
  if (RegExp(r'ofensivo|expl[ií]cito|vulgar').hasMatch(t)) return ContentWarning.explicit;
  return null;
}

_Doc _parse(EpubArchive archive, String path, List<MigrationIssue> issues) {
  try {
    final doc = parseXhtml(archive.text(path));
    final d = _Doc(path, doc);
    final body = bodyOf(doc);
    // El primer epub:type de un bloque dice qué era el documento.
    d.oldTypes = [
      ...?body?.descendants.whereType<XmlElement>().where((e) => !{'a', 'span', 'sup', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'img', 'p', 'small', 'big', 'b', 'i', 'em', 'strong', 'aside'}.contains(localName(e))).map(epubTypeOf).nonNulls.firstOrNull?.split(RegExp(r'\s+')),
    ];
    d.headings = body == null ? const [] : body.descendants.whereType<XmlElement>().where(isHeading).toList();
    return d;
  } on XmlException catch (e) {
    issues.add((level: MigrationIssueLevel.warning, message: 'No es XML bien formado; se copia sin migrar (${e.message}).', path: path));
    return _Doc(path, null)..notes.add('XHTML con errores');
  }
}

// Archivo → etiqueta de su primera entrada en el índice antiguo.
Map<String, String> _oldNav(EpubArchive archive) {
  final out = <String, String>{};
  if (archive.nav case final nav?) {
    try {
      final doc = parseXhtml(archive.text(nav.path));
      final toc = elementsOf(doc, 'nav').where((n) => (epubTypeOf(n) ?? '').split(' ').contains('toc')).firstOrNull;
      for (final a in toc == null ? const <XmlElement>[] : elementsOf(toc, 'a')) {
        out.putIfAbsent(resolvePath(nav.path, a.getAttribute('href') ?? ''), () => textOf(a));
      }
      return out;
    } on XmlException {
      return out;
    }
  }
  if (archive.ncx case final ncx?) {
    try {
      final doc = XmlDocument.parse(archive.text(ncx.path));
      for (final point in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'navPoint')) {
        final src = point.childElements.where((e) => e.name.local == 'content').firstOrNull?.getAttribute('src');
        final label = point.childElements.where((e) => e.name.local == 'navLabel').firstOrNull;
        if (src != null && label != null) out.putIfAbsent(resolvePath(ncx.path, src), () => textOf(label));
      }
    } on XmlException {
      return out;
    }
  }
  return out;
}

bool _hasCoverImage(_Doc d) => d.images.any((i) => i.getAttribute('role') == 'doc-cover');

void _classify(List<_Doc> docs, Map<String, String> oldNav) {
  _Doc? previous;
  var hasCover = false;
  String stemBase(String stem) => stem.replaceFirst(RegExp(r'[\s_-]+\d+$'), '').toLowerCase();
  for (final d in docs) {
    if (d.doc == null) {
      d.label = oldNav[d.path] ?? d.stem;
      previous = d;
      continue;
    }
    final mapped = d.oldTypes.map((t) => oldEpubTypes[t]).nonNulls.firstOrNull;
    var byFile = fileKind(d.stem);
    final visible = d.visible;
    // Sin encabezado, la entrada del índice antiguo dice qué es.
    var byHeading = headingKind(visible.isNotEmpty ? tocLabel(visible.first) : oldNav[d.path] ?? '');
    // Un encabezado oculto (a menudo copiado de la página anterior) no contradice al nombre del archivo.
    if (visible.isNotEmpty && byHeading != null && byFile != null && byFile != byHeading && classesOf(visible.first).any({'hidden', 'oculto'}.contains)) byHeading = null;
    final names = [for (final i in d.images) p.posix.basename(i.getAttribute('src') ?? '').toLowerCase()];
    final hasText = d.paragraphs.isNotEmpty;
    if (names.isNotEmpty && names.every((n) => RegExp(r'^(promo|publi|anuncio)').hasMatch(n))) {
      byFile = MigrationKind.promo;
    } else if (names.isNotEmpty && !hasText && names.every((n) => RegExp(r'^(logo|grupo|zeepubs)').hasMatch(n))) {
      byFile = MigrationKind.colophon;
    }
    var mappedKind = mapped;
    // Una ilustración intercalada en el cuerpo pertenece al capítulo en curso.
    if (byFile == MigrationKind.illustrations && previous != null && previous.kind.matter == BookMatter.body && visible.isEmpty) {
      byFile = null;
      if (mappedKind == MigrationKind.chapter || mappedKind == null) mappedKind = previous.kind;
    }
    // Una segunda «portada» solo por el nombre del archivo suele ser una portadilla.
    if (byFile == MigrationKind.cover && hasCover && !_hasCoverImage(d)) byFile = null;
    // «Capítulo…» y «Parte…» solo deciden si nada más da un tipo.
    final weakHeading = byHeading == MigrationKind.chapter || byHeading == MigrationKind.part ? byHeading : null;
    if (weakHeading != null) byHeading = null;
    if ((_hasCoverImage(d) || byFile == MigrationKind.cover) && !hasCover) {
      d.kind = MigrationKind.cover;
      hasCover = true;
    } else {
      d.kind = byHeading ?? (byFile != null && byFile != MigrationKind.chapter ? byFile : null) ?? mappedKind ?? byFile ?? weakHeading ?? MigrationKind.generic;
    }
    // El tipo antiguo «introduction» marcaba las ilustraciones; con texto es una introducción.
    if (d.kind == MigrationKind.illustrations && hasText) d.kind = MigrationKind.introduction;
    if (mappedKind != null && d.kind != mappedKind) d.notes.add('Era ${d.oldTypes.join(' ')}; por su ${byHeading != null ? 'encabezado' : 'nombre o contenido'} es ${d.kind.title.toLowerCase()}.');

    final listed = oldNav.containsKey(d.path);
    final hiddenHeading = visible.isNotEmpty && classesOf(visible.first).any({'hidden', 'oculto'}.contains);
    final excluded = visible.isNotEmpty && classesOf(visible.first).contains('sigil_not_in_toc') && !listed && (byHeading == null || byHeading == previous?.kind);
    final repeated = visible.isNotEmpty && previous != null && !listed && hiddenHeading && tocLabel(visible.first).toLowerCase() == previous.label.toLowerCase();
    final longText = d.paragraphs.length >= 15;
    if (previous != null && d.kind == previous.kind && groupKinds.contains(d.kind)) {
      // Grupo de páginas: todas forman la misma sección.
      _follow(d, previous);
      if (listed && !oldNav.containsKey(previous.path)) {
        previous
          ..label = oldNav[d.path]!
          ..inToc = true;
        d.label = previous.label;
      }
    } else if (repeated) {
      d.kind = previous.kind;
      _follow(d, previous);
    } else if (excluded && previous != null && d.kind == previous.kind) {
      _follow(d, previous);
    } else if (visible.isEmpty && previous != null && d.kind != MigrationKind.cover && stemBase(d.stem) == stemBase(previous.stem) && RegExp(r'[\s_-]\d+$').hasMatch(d.stem) && !listed && (byFile == null || byFile == previous.kind || byFile == fileKind(d.stem))) {
      // Otra parte del mismo archivo partido (Epilogo-00 → Epilogo-01).
      d.kind = previous.kind;
      _follow(d, previous);
    } else if (visible.isEmpty && previous != null && d.kind != MigrationKind.cover && (mappedKind == null || mappedKind == previous.kind) && (byFile == null || byFile == previous.kind) && !(listed && oldNav[d.path] != oldNav[previous.path]) && !(longText && const {MigrationKind.cover, MigrationKind.titlePage, MigrationKind.colophon, MigrationKind.contentsImage, MigrationKind.illustrations}.contains(previous.kind))) {
      d.kind = previous.kind;
      _follow(d, previous);
    } else if (visible.isNotEmpty && localName(visible.first) != 'h1' && previous != null && d.kind == previous.kind && byHeading == null) {
      _follow(d, previous);
    } else if (visible.isEmpty && mappedKind == null && byFile == null) {
      d.notes.add('Sin encabezado ni tipo reconocible.');
    }
    if (!d.continuation) {
      final primary = visible.firstOrNull;
      d.label = primary != null ? tocLabel(primary) : oldNav[d.path] ?? d.kind.title;
      d.inToc = primary != null ? !classesOf(primary).contains('sigil_not_in_toc') || listed : listed;
      if (primary != null && listed && (oldNav[d.path] ?? '').isNotEmpty && classesOf(primary).any({'hidden', 'oculto'}.contains)) d.label = oldNav[d.path]!;
      previous = d;
    }
  }
}

void _follow(_Doc d, _Doc previous) {
  d
    ..continuation = true
    ..label = previous.label
    ..inToc = false;
}

// La división sale del tipo, pero la posición manda: nunca se vuelve a una división anterior.
void _assignMatter(List<_Doc> docs) {
  final defaults = [for (final d in docs) d.kind.matter?.index];
  // Menor división que aún queda por delante desde cada posición.
  final ahead = List.filled(docs.length + 1, BookMatter.back.index);
  for (var i = docs.length - 1; i >= 0; i--) {
    ahead[i] = min(defaults[i] ?? ahead[i + 1], ahead[i + 1]);
  }
  var current = 0;
  for (final (i, d) in docs.indexed) {
    if (defaults[i] case final matter?) {
      current = max(current, min(matter, ahead[i]));
      if (current != matter) d.notes.add('Va en ${BookMatter.values[current].label.toLowerCase()} por su posición.');
    }
    d.matter = BookMatter.values[current];
    // Palabras del autor antes del texto: es un prefacio.
    if (d.kind == MigrationKind.afterword && d.matter == BookMatter.front) d.kind = MigrationKind.preface;
  }
}

List<String> _standardNames(List<_Doc> docs) {
  final counters = <String, int>{};
  String? owner;
  final names = <String>[];
  for (final d in docs) {
    if (d.continuation && owner != null) {
      names.add(owner);
      continue;
    }
    var base = labelFileNames.where((n) => n.$1.hasMatch(d.label.trim())).firstOrNull?.$2 ?? d.kind.fileName;
    if (d.kind == MigrationKind.chapter && RegExp(r'^interlud(io|e)', caseSensitive: false).hasMatch(d.label)) base = 'interludio';
    if (d.kind.numbered || base == 'interludio') {
      counters[base] = (counters[base] ?? 0) + 1;
      base = '$base${counters[base].toString().padLeft(2, '0')}';
    }
    owner = base;
    names.add(base);
  }
  // Los repetidos (dos «autor») se numeran desde el segundo.
  final seen = <String, int>{};
  for (final (i, name) in names.indexed) {
    if (docs[i].continuation) continue;
    seen[name] = (seen[name] ?? 0) + 1;
    if (seen[name]! > 1) names[i] = '$name-${seen[name]}';
  }
  return names;
}

BookMetadata _metadata(EpubArchive archive) {
  var m = OpfMetadata(archive.text(archive.opfPath)).read();
  final isbn13 = m.isbn13.trim().isNotEmpty ? m.isbn13 : isbn13From10(m.isbn10) ?? '';
  final isbn10 = m.isbn10.trim().isNotEmpty ? m.isbn10 : isbn10From13(m.isbn13) ?? '';
  // Fecha con el día en lugar del mes (2017-25-03): se invierten.
  final swapped = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(m.date.trim());
  if (swapped != null && int.parse(swapped[2]!) > 12 && int.parse(swapped[3]!) <= 12) {
    m = m.copyWith(date: m.date.trim().replaceRange(5, 10, '${swapped[3]}-${swapped[2]}'));
  }
  m = m.copyWith(isbn13: isbn13.isEmpty ? '' : formatIsbn(isbn13, isbn13Groups), isbn10: isbn10.isEmpty ? '' : formatIsbn(isbn10, isbn10Groups));
  // El principal que no está en inglés se conserva también como equivalente de su idioma.
  String langOf(String lang) => lang.trim().isEmpty ? m.language : lang;
  if (m.title.trim().isNotEmpty && langOf(m.titleLang) != mainTitleLanguage && localizedText(m.altTitles, langOf(m.titleLang)).trim().isEmpty) {
    m = m.copyWith(altTitles: withLocalizedText(m.altTitles, langOf(m.titleLang), m.title.replaceFirst(RegExp(r'\s*\[[^\[\]]*\]\s*$'), '')));
  }
  if (m.hasSeries && langOf(m.seriesLang) != mainTitleLanguage && localizedText(m.altSeries, langOf(m.seriesLang)).trim().isEmpty) {
    m = m.copyWith(altSeries: withLocalizedText(m.altSeries, langOf(m.seriesLang), m.series.replaceFirst(RegExp(r'\s*\[[^\[\]]*\]\s*$'), '')));
  }
  return m;
}

typedef _Styles = ({Map<String, List<String>> renames, List<String> unknown, String customCss, List<String> sheets});

// Clases antiguas → nuevas según lo que hace su regla, y lo propio del libro como CSS.
_Styles _styles(EpubArchive archive, List<String> cssPaths, Set<String> used, Set<String> templateClasses, String templateCss, LegacyTemplates? oldTemplates) {
  final stylePath = cssPaths.where((x) => p.posix.basename(x).toLowerCase() == 'style.css').firstOrNull ?? cssPaths.firstOrNull;
  final rules = [
    for (final path in cssPaths)
      if (path == stylePath || _navSheets.hasMatch(p.posix.basename(path)))
        for (final r in parseCss(archive.text(path))) (rule: r, sheet: path),
  ];
  final byClass = <String, List<CssRule>>{};
  for (final (:rule, sheet: _) in rules) {
    for (final c in selectorsOf(rule.prelude).expand(classNames)) {
      byClass.putIfAbsent(c, () => []).add(rule);
    }
  }

  // Fuentes incrustadas declaradas en la hoja, con su archivo.
  final faces = <String, List<CssRule>>{};
  for (final (:rule, :sheet) in rules) {
    if (rule.prelude != '@font-face') continue;
    final family = fontFamilies(declaration(rule.body, 'font-family') ?? '').firstOrNull;
    final src = RegExp(r'''url\(\s*["']?([^"')]+)''').firstMatch(rule.body)?.group(1);
    if (family != null && src != null && archive.files.containsKey(resolvePath(sheet, src))) faces.putIfAbsent(family, () => []).add(rule);
  }

  final renames = <String, List<String>>{};
  for (final c in used) {
    final classRules = byClass[c] ?? const <CssRule>[];
    final sizing = classRules.where((r) => r.body.contains('width') || r.body.contains('height')).toList();
    if (_imageDefaults.containsKey(c) || (!textClassMap.containsKey(c) && !templateClasses.contains(c) && sizing.isNotEmpty && sizing.any((r) => RegExp(r'\b(img|figure)\b').hasMatch(r.prelude)))) {
      final role = _imageRole(c, sizing);
      if (role == null) continue;
      final align = classRules.map((r) => declaration(r.body, 'text-align')).where((a) => a == 'left' || a == 'right').firstOrNull;
      renames[c] = [if (role.isNotEmpty) role, if (role.isNotEmpty && align != null) 'align-$align'];
    } else if (textClassMap.containsKey(c)) {
      renames[c] = textClassMap[c]!;
    }
  }

  final fontsUsed = <String>{};
  final headingFonts = <String, Set<int>>{};
  final fallback = <String, String>{};
  final custom = <String>[];
  // Declaraciones que ya viajan con su regla entera: «contexto|selector|propiedad».
  final carried = <String>{};
  String renamed(String selector) => selector.replaceAllMapped(RegExp(r'\.([A-Za-z_][\w-]*)'), (m) => '.${renames[m[1]]?.firstOrNull ?? m[1]}');
  for (final (:rule, sheet: _) in rules) {
    if (rule.prelude.startsWith('@') || (rule.context.isNotEmpty && !rule.context.startsWith('@media'))) continue;
    final keep = <String>[];
    final families = fontFamilies(declaration(rule.body, 'font-family') ?? '');
    for (final selector in selectorsOf(rule.prelude)) {
      if (selector == '.fuente') {
        if (families.isNotEmpty && faces.containsKey(families.first) && used.contains('fuente')) {
          renames['fuente'] = [fontClass(families.first)];
          fontsUsed.add(families.first);
          fallback[families.first] = families.firstWhere(_genericFamilies.contains, orElse: () => 'serif');
        }
        continue;
      }
      final next = renamed(selector);
      // La fuente de un nivel de título se declara como en el template.
      final level = RegExp(r'^h([1-6])$').firstMatch(next)?.group(1);
      if (level != null && rule.context.isEmpty && families.isNotEmpty && faces.containsKey(families.first)) {
        headingFonts.putIfAbsent(families.first, () => {}).add(int.parse(level));
        fallback[families.first] = families.firstWhere(_genericFamilies.contains, orElse: () => 'serif');
        fontsUsed.add(families.first);
        continue;
      }
      final own = classNames(next).where((c) => !templateClasses.contains(c) && !c.startsWith('font-')).toList();
      if (rule.own || own.any(used.contains)) {
        keep.add(next);
        carried.addAll([for (final d in declarations(rule.body)) '${rule.context}|${normalizeSelector(selector)}|${d.$1}']);
      }
    }
    if (keep.isEmpty) continue;
    var body = rule.body;
    // Las medidas de las clases de imagen las pone el template; se conserva el resto.
    if (keep.any((s) => RegExp(r'\.(fill|icon|text|logo)\b').hasMatch(s))) {
      body = declarations(body).where((d) => d.$1 != 'width' && d.$1 != 'height').map((d) => '${d.$1}: ${d.$2}').join('; ');
    }
    if (body.trim().isEmpty) continue;
    final text = prettyRule(keep.join(', '), body);
    custom.add(rule.context.isEmpty ? text : '${rule.context} {\n${text.split('\n').map((l) => '  $l').join('\n')}\n}');
    fontsUsed.addAll(families.where(faces.containsKey));
  }

  final adjustments = stylePath == null || oldTemplates == null
      ? const <String>[]
      : _adjustments(legacyDeltas(archive.text(stylePath), oldTemplates), StyleSheetValues(templateCss), renamed, used, carried, faces.keys.toSet(), fontsUsed);

  final fontCss = <String>[];
  final sortedFonts = fontsUsed.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  for (final family in sortedFonts) {
    for (final face in faces[family]!) {
      final src = RegExp(r'''url\(\s*["']?([^"')]+)''').firstMatch(face.body)!.group(1)!;
      final sheet = rules.firstWhere((r) => identical(r.rule, face)).sheet;
      final file = resolvePath(sheet, src);
      fontCss.add('@font-face {\n  font-family: "$family";\n  font-weight: ${declaration(face.body, 'font-weight') ?? 'normal'};\n  font-style: ${declaration(face.body, 'font-style') ?? 'normal'};\n  src: url(../Fonts/${fontFileName(file)});\n}');
    }
    final levels = (headingFonts[family] ?? const <int>{}).toList()..sort();
    // El título y el subtítulo de la página de título no heredan la fuente de los encabezados: conservan la de la
    // plantilla, o la suya si el libro les puso una propia.
    final selectors = [
      for (final level in levels) 'h$level',
      '.${fontClass(family)}',
    ];
    fontCss.add('${selectors.join(',\n')} {\n  font-family: "$family", ${fallback[family] ?? 'serif'};\n}');
  }

  final known = {...templateClasses, ...renames.keys, ...renames.values.expand((x) => x)};
  final customClasses = custom.expand((r) => classNames(r)).toSet();
  final unknown = [
    for (final c in used)
      if (!known.contains(c) && !customClasses.contains(c)) c,
  ]..sort();
  return (
    sheets: [
      for (final path in cssPaths)
        if (path == stylePath || _navSheets.hasMatch(p.posix.basename(path))) path,
    ],
    renames: renames,
    unknown: unknown,
    customCss: [
      ...custom,
      if (fontCss.isNotEmpty) '/* Fuentes incrustadas */',
      ...fontCss,
      if (adjustments.isNotEmpty) '/* Ajustes de este libro sobre el template */',
      ...adjustments,
    ].join('\n'),
  );
}

const _imageRoles = {'fill', 'icon', 'text', 'logo'};
const _sizing = {'width', 'height', 'max-width', 'max-height', 'min-width', 'min-height'};
const _templateOwned = {'break-before', 'break-after', 'no-break-inside', 'hidden', 'sigil_split_marker'};
final _navSelector = RegExp(r'(?<![\w.#-])nav(?![\w-])|epub\|type');
final _imageSelector = RegExp(r'(?<![\w.#-])(img|figure|svg)(?![\w-])');

// Reglas que devuelven al libro lo que cambió sobre el template anterior y el actual no da por sí
// solo. Van al final de la hoja, así que ganan a las reglas del template con el mismo selector.
List<String> _adjustments(
  List<StyleDelta> deltas,
  StyleSheetValues template,
  String Function(String) renamed,
  Set<String> used,
  Set<String> carried,
  Set<String> embedded,
  Set<String> fontsUsed,
) {
  // <big> pasa a ser un span con la clase large.
  String target(String selector) => normalizeSelector(renamed(selector.replaceAll(RegExp(r'(?<![\w.#-])big(?![\w-])'), '.large')));
  final changed = {for (final d in deltas) '${d.context}|${target(d.selector)}|${d.property}'};
  final groups = <(String, String), Map<String, String>>{};
  for (final d in deltas) {
    if (carried.contains('${d.context}|${d.selector}|${d.property}') || _navSelector.hasMatch(d.selector)) continue;
    final oldClasses = classNames(d.selector);
    if (oldClasses.contains('fuente') || !oldClasses.every(used.contains)) continue;
    final selector = target(d.selector);
    final classes = classNames(selector).toSet();
    if (classes.any(_templateOwned.contains)) continue;
    if ((classes.any(_imageRoles.contains) || _imageSelector.hasMatch(selector)) && _sizing.contains(d.property)) {
      // Las medidas de imagen las pone el template; solo un logo con ancho propio conserva el suyo.
      final width = _number(d.value, '%');
      if (!(d.property == 'width' && classes.contains('logo') && width != null && (width - 54).abs() > 10)) continue;
    }
    if (d.property == 'font-family') {
      final family = fontFamilies(d.value).firstOrNull;
      if (embedded.contains(family)) {
        // La fuente de un nivel de título se declara con las fuentes incrustadas.
        if (RegExp(r'^h[1-6]$').hasMatch(d.selector)) continue;
        fontsUsed.add(family!);
      }
    }
    // Si el libro también cambia el selector del que este hereda, el valor heredado del template ya no sirve.
    final inheritedChanged = changed.contains('${d.context}|${StyleSheetValues.fallbackOf(selector)}|${d.property}');
    final current = inheritedChanged ? template.own((d.context, selector), d.property) : template.values((d.context, selector), d.property);
    if ((current == null && d.removed) || (current ?? const []).any((v) => normalizeValue(v) == normalizeValue(d.value))) continue;
    groups.putIfAbsent((d.context, selector), () => {})[d.property] = d.value;
  }
  // Selectores con las mismas declaraciones comparten regla.
  final merged = <String, ({String context, List<String> selectors, Map<String, String> declarations})>{};
  for (final MapEntry(key: (context, selector), value: declarations) in groups.entries) {
    merged.putIfAbsent('$context|$declarations', () => (context: context, selectors: [], declarations: declarations)).selectors.add(selector);
  }
  return [
    for (final (:context, :selectors, :declarations) in merged.values)
      () {
        final text = '${selectors.join(',\n')} {\n${declarations.entries.map((d) => '  ${d.key}: ${d.value};\n').join()}}';
        return context.isEmpty ? text : '$context {\n${text.split('\n').map((l) => '  $l').join('\n')}\n}';
      }(),
  ];
}

double? _number(String? value, String unit) => value == null ? null : double.tryParse(RegExp('^([\\d.]+)$unit\$').firstMatch(value.trim())?.group(1) ?? '');

// Papel de una clase de imagen por sus medidas; vacío = sin clase; null = no es de imagen.
String? _imageRole(String name, List<CssRule> rules) {
  String? value(String prop) => rules.map((r) => declaration(r.body, prop)).where((v) => v != null && v != 'auto').firstOrNull;
  final width = value('width');
  final height = value('height');
  if ((width != null && _number(width, '%') == 100 && (height == null || _number(height, '%') == 100)) || (height != null && height.contains('vh'))) {
    return name == 'vertical' || name == 'imgtitulo' ? '' : 'fill';
  }
  final em = _number(height, 'em') ?? _number(height, 'lh');
  if (em != null) return em <= 1.6 ? 'text' : 'icon';
  if (width != null && RegExp(r'^[\d.]+ex$').hasMatch(width)) return 'text';
  final percent = _number(width, '%');
  if (percent != null) return percent >= 25 ? 'logo' : 'icon';
  return _imageDefaults[name];
}
