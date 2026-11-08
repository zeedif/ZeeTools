import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '/features/epub_templater/data/opf_metadata.dart';
import '/features/epub_templater/domain/section_kind.dart';
import '../domain/migration_kind.dart';
import '../domain/migration_project.dart';
import 'epub_archive.dart';
import 'migration_analyzer.dart';
import 'xhtml_utils.dart';

const _headingId = 'encabezado';
// Las rutas internas se escriben absolutas mientras se mueven documentos y se
// vuelven relativas al final; un href de EPUB nunca empieza por esta marca.
const _absolute = '\u0000/';
const _mediaTypes = {
  'xhtml': 'application/xhtml+xml',
  'html': 'application/xhtml+xml',
  'css': 'text/css',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'svg': 'image/svg+xml',
  'ttf': 'font/ttf',
  'otf': 'font/otf',
  'woff': 'font/woff',
  'woff2': 'font/woff2',
  'js': 'application/javascript',
  'smil': 'application/smil+xml',
};
// Restos de otras herramientas que no forman parte del libro.
final _junk = RegExp(r'(^|/)(calibre_bookmarks\.txt|itunesmetadata\.plist|\.ds_store|thumbs\.db)$', caseSensitive: false);

typedef MigratedEpub = ({Uint8List bytes, List<MigrationIssue> notes});

class _Final {
  _Final(this.doc, this.source, this.path, this.xml);

  final MigrationDoc doc;
  final String source;
  final String path;
  final XmlDocument? xml;
}

// Construye el EPUB con la estructura del template a partir del original y de lo
// decidido en [project].
MigratedEpub writeMigratedEpub(
  EpubArchive archive,
  MigrationProject project, {
  required String templateCss,
  required String navCss,
  required Uint8List zeepubsLogo,
  DateTime? now,
}) {
  final notes = <MigrationIssue>[];
  void note(String message, [String? path]) => notes.add((level: MigrationIssueLevel.info, message: message, path: path));
  final lang = project.metadata.language.trim().isEmpty ? 'es' : project.metadata.language.trim();
  final opfDir = p.posix.dirname(archive.opfPath) == '.' ? '' : p.posix.dirname(archive.opfPath);
  String inOpf(String path) => opfDir.isEmpty ? path : '$opfDir/$path';
  final textDir = project.docs.isEmpty ? inOpf('Text') : p.posix.dirname(project.docs.first.path);
  final stylePath = inOpf('Styles/style.css');
  final navStylePath = inOpf('Styles/nav-style.css');

  // Documentos que quedan y a cuál se une cada continuación.
  final docs = <String, XmlDocument?>{};
  for (final d in project.docs) {
    docs[d.path] = d.broken ? null : parseXhtml(archive.text(d.path));
  }
  final finals = <_Final>[];
  final usedNames = <String>{};
  final mergedInto = <String, _Final>{};
  for (final d in project.docs) {
    if (d.continuation && !d.broken && finals.isNotEmpty && finals.last.xml != null) {
      mergedInto[d.path] = finals.last;
      continue;
    }
    var name = d.fileName.trim().isEmpty ? d.kind.fileName : d.fileName.trim();
    for (var n = 2; !usedNames.add(name.toLowerCase()); n++) {
      name = '${d.fileName}-$n';
    }
    finals.add(_Final(d, d.path, '$textDir/$name.xhtml', docs[d.path]));
  }

  // Todas las rutas internas, absolutas; se recogen los destinos con fragmento.
  final referenced = <String>{};
  for (final MapEntry(key: path, value: xml) in docs.entries) {
    if (xml == null) continue;
    for (final e in xml.descendants.whereType<XmlElement>()) {
      for (final attr in [...e.attributes]) {
        if (!const {'href', 'src', 'xlink:href'}.contains(attr.name.qualified)) continue;
        final value = attr.value.trim();
        if (value.isEmpty || isExternal(value)) continue;
        final target = value.startsWith('#') ? path : resolvePath(path, value);
        final fragment = value.contains('#') ? value.substring(value.indexOf('#') + 1) : '';
        if (fragment.isNotEmpty) referenced.add('$target#$fragment');
        attr.value = '$_absolute$target${fragment.isEmpty ? '' : '#$fragment'}';
      }
    }
  }

  // Hojas propias del libro que no sustituye el template y siguen en él.
  final sheets = {
    for (final i in archive.manifest)
      if (i.mediaType == 'text/css' && archive.files.containsKey(i.path) && !project.replacedSheets.contains(i.path)) i.path,
  };
  final notesDoc = finals.where((f) => f.doc.kind == MigrationKind.endnotes).firstOrNull;
  for (final f in finals) {
    if (f.xml == null) continue;
    _normalize(f.xml!, f.doc, project, lang: lang, referenced: referenced, styleHref: relativePath(f.path, stylePath), source: f.source, sheets: sheets, note: (m) => note(m, f.source));
  }
  for (final d in project.docs) {
    if (mergedInto.containsKey(d.path)) _cleanBlocks(docs[d.path]!, project, (m) => note(m, d.path));
  }
  final pageFigures = <XmlElement>{
    for (final xml in docs.values.nonNulls) ?_pageFigure(xml),
  };

  // Continuaciones: su contenido pasa al final del documento al que pertenecen, tras un salto.
  final remap = <String, (String, String)>{for (final f in finals) f.source: (f.path, '')};
  final idMap = <String, String>{};
  for (final d in project.docs) {
    final target = mergedInto[d.path];
    if (target == null) continue;
    final section = _container(target.xml!);
    final body = bodyOf(docs[d.path]!);
    if (body == null) continue;
    final source = body.childElements.length == 1 && localName(body.childElements.first) == 'section' ? body.childElements.first : body;
    final taken = {for (final e in target.xml!.descendants.whereType<XmlElement>()) ?e.getAttribute('id')};
    for (final e in source.descendants.whereType<XmlElement>()) {
      final id = e.getAttribute('id');
      if (id == null) continue;
      if (taken.contains(id)) {
        var fresh = id;
        for (var n = 2; taken.contains(fresh); n++) {
          fresh = '${id}_$n';
        }
        idMap['${d.path}#$id'] = fresh;
        e.setAttribute('id', fresh);
      }
      taken.add(e.getAttribute('id')!);
    }
    final group = groupKinds.contains(d.kind);
    if (group) {
      for (final h in source.descendants.whereType<XmlElement>().where(isHeading).toList()) {
        if (classesOf(h).any({'hidden', 'oculto'}.contains) || headingLabel(h).isEmpty) {
          h.remove();
        } else {
          setClasses(h, [...classesOf(h), 'sigil_not_in_toc']);
        }
      }
    }
    final chunk = source.childElements.toList();
    var anchor = '';
    if (chunk.isNotEmpty) {
      final first = chunk.firstWhere(isHeading, orElse: () => chunk.first);
      if (!group) {
        anchor = first.getAttribute('id') ?? p.posix.basenameWithoutExtension(d.path).replaceAll(RegExp(r'[^\w-]'), '_');
        while (first.getAttribute('id') == null && taken.contains(anchor)) {
          anchor = '_$anchor';
        }
        first.setAttribute('id', anchor);
        taken.add(anchor);
      }
      setClasses(chunk.first, [...classesOf(chunk.first), 'break-before']);
      section.children.add(XmlText('\n\n    '));
      for (final c in chunk) {
        c.remove();
        section.children
          ..add(c)
          ..add(XmlText('\n    '));
      }
    }
    remap[d.path] = (target.path, anchor);
  }
  if (mergedInto.isNotEmpty) note('${mergedInto.length} documentos unidos a su sección.');
  for (final f in finals) {
    if (f.xml != null) _finishKind(f.xml!, f.doc, project);
  }

  // Advertencia y logos que el libro no tenía.
  var cover = finals.indexWhere((f) => f.doc.kind == MigrationKind.cover);
  if (project.addNotice && !finals.any((f) => f.doc.kind == MigrationKind.notice)) {
    final path = '$textDir/advertencia.xhtml';
    finals.insert(cover + 1, _Final(MigrationDoc(path: path, kind: MigrationKind.notice, matter: BookMatter.front, label: 'Advertencia', inToc: false, fileName: 'advertencia'), path, path, parseXhtml(_page(lang, 'Advertencia', relativePath(path, stylePath), BookMatter.front, '<section epub:type="notice" role="doc-notice" aria-label="Advertencia">\n    ${_warningBlock(project)}\n  </section>'))));
  }
  final logoPath = inOpf('Images/zeepubs.png');
  final addLogos = project.addLogos && !finals.any((f) => f.doc.kind == MigrationKind.colophon);
  if (addLogos) {
    final path = '$textDir/logos.xhtml';
    final title = finals.indexWhere((f) => f.doc.kind == MigrationKind.titlePage);
    cover = finals.indexWhere((f) => f.doc.kind == MigrationKind.cover);
    final at = title >= 0 ? title + 1 : cover + 1;
    finals.insert(at, _Final(MigrationDoc(path: path, kind: MigrationKind.colophon, matter: BookMatter.front, label: 'Logos', inToc: false, fileName: 'logos'), path, path, parseXhtml(_page(lang, 'Logos', relativePath(path, stylePath), BookMatter.front, '<section epub:type="colophon" role="doc-colophon" aria-label="Logos">\n    <figure class="logo"><img class="space-3" src="${relativePath(path, logoPath)}" alt="Logo zeepubs"/></figure>\n  </section>'))));
  }

  // Nombres con espacios: no son URL válidas dentro del EPUB.
  final safe = <String, String>{
    for (final path in archive.files.keys)
      if (RegExp(r'\s').hasMatch(p.posix.basename(path)) && !docs.containsKey(path)) path: p.posix.join(p.posix.dirname(path), p.posix.basename(path).replaceAll(RegExp(r'\s+'), '_')),
  };
  for (final MapEntry(key: from, value: to) in safe.entries) {
    note('Renombrado a ${p.posix.basename(to)}.', from);
  }

  // Enlaces relativos a la ubicación final; las llamadas a notas se marcan.
  for (final f in finals) {
    if (f.xml == null) continue;
    for (final e in f.xml!.descendants.whereType<XmlElement>()) {
      for (final attr in [...e.attributes]) {
        if (!attr.value.startsWith(_absolute)) continue;
        final raw = attr.value.substring(_absolute.length);
        final hash = raw.indexOf('#');
        final path = hash < 0 ? raw : raw.substring(0, hash);
        var fragment = hash < 0 ? '' : raw.substring(hash + 1);
        final (dest, anchor) = remap[path] ?? (safe[path] ?? path, '');
        fragment = fragment.isEmpty ? anchor : idMap['$path#$fragment'] ?? fragment;
        final href = dest == f.path && fragment.isNotEmpty ? '' : relativePath(f.path, dest);
        attr.value = '$href${fragment.isEmpty ? '' : '#$fragment'}';
        if (notesDoc != null && dest == notesDoc.path && f != notesDoc && localName(e) == 'a' && fragment.isNotEmpty) {
          setEpubType(e, 'noteref');
          e.setAttribute('role', 'doc-noteref');
        }
      }
    }
    _dedupeIds(f.xml!);
    _fillBreaks(f.xml!, f.path, archive, pageFigures);
  }

  // Hojas de estilo, fuentes y archivos que el template sustituye.
  final drop = <String>{
    ?archive.nav?.path,
    ?archive.ncx?.path,
    for (final d in project.docs) d.path,
    ...project.replacedSheets,
    for (final path in archive.files.keys)
      if (_junk.hasMatch(path)) path,
  };
  final css = '${templateCss.replaceAll('\r\n', '\n').split('\n').where((l) => !const ['/* Reglas propias de cada libro; quitar las que no se usen */', '/* Niveles 7 a 9: <p class="h7" role="heading" aria-level="7"> */'].contains(l.trim())).join('\n').trimRight()}\n${project.customCss.trim().isEmpty ? '' : '${project.customCss.trim()}\n'}';
  final fontFiles = {for (final m in RegExp(r'''url\(\s*["']?\.\./Fonts/([^"')]+)''').allMatches(css)) m[1]!};
  final fonts = <String, String>{};
  for (final i in archive.manifest) {
    final isFont = i.mediaType.contains('font') || RegExp(r'\.(ttf|otf|woff2?)$', caseSensitive: false).hasMatch(i.path);
    if (!isFont) continue;
    drop.add(i.path);
    if (fontFiles.contains(fontFileName(i.path))) {
      fonts[i.path] = inOpf('Fonts/${fontFileName(i.path)}');
    } else {
      note('Fuente sin uso quitada: ${p.posix.basename(i.path)}.', i.path);
    }
  }

  final out = <String, Uint8List>{};
  void text(String path, String content) => out[path] = Uint8List.fromList(utf8.encode(content));
  final navPath = '$textDir/toc.xhtml';
  text(navPath, _nav(finals, navPath, lang, relativePath(navPath, stylePath), relativePath(navPath, navStylePath)));
  for (final f in finals) {
    if (f.xml == null) {
      out[f.path] = archive.files[f.source]!;
    } else {
      text(f.path, _serialize(f.xml!));
    }
  }
  text(stylePath, css);
  text(navStylePath, navCss);
  for (final MapEntry(key: from, value: to) in fonts.entries) {
    out[to] = archive.files[from]!;
  }
  if (addLogos) out[logoPath] = zeepubsLogo;
  for (final MapEntry(key: path, value: bytes) in archive.files.entries) {
    if (drop.contains(path) || out.containsKey(path) || path == archive.opfPath || path == 'mimetype' || path.startsWith('META-INF/')) continue;
    if (!archive.manifest.any((i) => i.path == path)) {
      note('Archivo fuera del manifiesto quitado.', path);
      continue;
    }
    out[safe[path] ?? path] = bytes;
  }
  text(archive.opfPath, _opf(archive, project, finals, out, navPath, lang, now ?? DateTime.now().toUtc()));

  final zip = Archive()..addFile(ArchiveFile.noCompress('mimetype', 20, utf8.encode('application/epub+zip')));
  for (final MapEntry(key: path, value: bytes) in archive.files.entries) {
    if (path.startsWith('META-INF/')) zip.addFile(ArchiveFile(path, bytes.length, bytes));
  }
  for (final MapEntry(key: path, value: bytes) in out.entries) {
    zip.addFile(ArchiveFile(path, bytes.length, bytes));
  }
  return (bytes: ZipEncoder().encodeBytes(zip), notes: notes);
}

String _page(String lang, String title, String styleHref, BookMatter matter, String section) =>
    '''<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="$lang" xml:lang="$lang">
<head>
  <meta charset="utf-8"/>
  <title>${escapeXml(title)}</title>
  <link href="$styleHref" rel="stylesheet" type="text/css"/>
</head>
<body epub:type="${matter.epubType}">
  $section
</body>
</html>
''';

// Las notas seguidas forman una lista, como en la plantilla: los lectores la muestran en la página y abren cada
// elemento en la ventana de la nota. El enlace de vuelta solo envuelve el número para que el texto no sea un enlace.
void _noteList(XmlElement section) {
  XmlElement? list;
  for (final div in elementsOf(section, 'div').where((e) => classesOf(e).contains('note')).toList()) {
    final holder = div.descendants.whereType<XmlElement>().where((e) => e.getAttribute('id') != null).firstOrNull;
    final item = _el('li', {'id': ?(div.getAttribute('id') ?? holder?.getAttribute('id'))});
    holder?.removeAttribute('id');
    final children = [...div.children];
    for (final c in children) {
      c.remove();
    }
    item.children.addAll(children);
    final backlink = elementsOf(item, 'a').where((a) => (a.getAttribute('href') ?? '').contains('#')).firstOrNull;
    if (backlink != null) {
      backlink.setAttribute('role', 'doc-backlink');
      final number = backlink.childElements.where((e) => localName(e) == 'sup').firstOrNull;
      if (number != null) {
        final rest = backlink.children.skip(backlink.children.indexOf(number) + 1).toList();
        for (final n in rest) {
          n.remove();
        }
        backlink.parent!.children.insertAll(backlink.parent!.children.indexOf(backlink) + 1, rest);
      }
    }
    final parent = div.parent!;
    if (list != null && list.parent == parent && div.previousElementSibling == list) {
      div.remove();
    } else {
      list = _el('ol', {'class': 'notes'});
      parent.children[parent.children.indexOf(div)] = list;
    }
    list.children.add(item);
  }
}

String _warningBlock(MigrationProject project) => '<blockquote class="warning">\n      <p class="large align-center"><b>Advertencia:</b></p>\n      <p class="space-0">${escapeXml(project.warning.text)}</p>\n    </blockquote>';

const _voidElements = {'meta', 'link', 'img', 'br', 'hr', 'col', 'source', 'wbr'};

XmlElement _el(String tag, [Map<String, String> attributes = const {}, List<XmlNode> children = const []]) => XmlElement.tag(tag, attributes: [for (final MapEntry(:key, :value) in attributes.entries) XmlAttribute(XmlName.qualified(key), value)], children: children, isSelfClosing: _voidElements.contains(tag));

String _serialize(XmlDocument doc) => '<?xml version="1.0" encoding="utf-8"?>\n<!DOCTYPE html>\n${doc.rootElement.toXmlString()}\n';

XmlElement _container(XmlDocument doc) {
  final body = bodyOf(doc)!;
  return body.childElements.length == 1 && localName(body.childElements.first) == 'section' ? body.childElements.first : body;
}

void _unwrap(XmlElement e) {
  final parent = e.parent!;
  final index = parent.children.indexOf(e);
  final children = [...e.children];
  for (final c in children) {
    c.remove();
  }
  e.remove();
  parent.children.insertAll(index, children);
}

// Lo que se corrige en todo documento, también en las continuaciones.
void _cleanBlocks(XmlDocument doc, MigrationProject project, void Function(String message) note) {
  for (final c in doc.descendants.whereType<XmlComment>().toList()) {
    c.remove();
  }
  for (final e in doc.descendants.whereType<XmlElement>().toList()) {
    final classes = classesOf(e);
    if (classes.isNotEmpty) {
      setClasses(e, [
        for (final c in classes) ...(project.classRenames[c] ?? [c]),
      ]);
    }
    // <big> no existe en HTML5; .large tiene el mismo tamaño.
    if (localName(e) == 'big') {
      final span = _el('span', {
        'class': ['large', ...classesOf(e)].join(' '),
      });
      final parent = e.parent!;
      final children = [...e.children];
      for (final c in children) {
        c.remove();
      }
      span.children.addAll(children);
      parent.children[parent.children.indexOf(e)] = span;
    }
    if (localName(e) == 'style' && e.ancestors.whereType<XmlElement>().any((a) => localName(a) == 'body')) e.remove();
  }
  final body = bodyOf(doc);
  if (body == null) return;
  // Los envoltorios <header> que solo agrupan encabezados sobran.
  for (final header in elementsOf(body, 'header').toList()) {
    if (header.childElements.every(isHeading)) _unwrap(header);
  }
  // La semántica pasa a la sección: se quita de bloques internos que la repetían.
  for (final e in body.descendants.whereType<XmlElement>()) {
    final types = (epubTypeOf(e) ?? '').split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    if (types.any(oldEpubTypes.containsKey) && const {'figure', 'blockquote', 'div', 'section'}.contains(localName(e)) && e.parent != body) {
      setEpubType(e, null);
      e.removeAttribute('aria-label');
      final role = e.getAttribute('role') ?? '';
      if (role.startsWith('doc-') && role != 'doc-cover') e.removeAttribute('role');
    }
    final role = e.getAttribute('role');
    if (role == 'doc-subtitle' && !isHeading(e)) e.removeAttribute('role');
    if (role == 'doc-endnote' || role == 'doc-biblioentry') e.removeAttribute('role');
  }
  _fixHtml(body, note);
  // Las imágenes sueltas entre bloques van en una figura.
  for (final img in elementsOf(body, 'img').toList()) {
    final parent = img.parent;
    if (parent is! XmlElement || !const {'section', 'div', 'body', 'blockquote', 'aside'}.contains(localName(parent))) continue;
    final figure = _el('figure');
    final classes = classesOf(img);
    if (classes.contains('text')) {
      setClasses(figure, ['text']);
      setClasses(img, classes.where((c) => c != 'text').toList());
    }
    parent.children[parent.children.indexOf(img)] = figure;
    figure.children.add(img);
  }
}

void _normalize(
  XmlDocument doc,
  MigrationDoc d,
  MigrationProject project, {
  required String lang,
  required Set<String> referenced,
  required String styleHref,
  required String source,
  required Set<String> sheets,
  required void Function(String message) note,
}) {
  _cleanBlocks(doc, project, note);
  final root = doc.rootElement;
  for (final attr in [...root.attributes]) {
    if (!attr.name.qualified.startsWith('xmlns')) root.removeAttribute(attr.name.qualified);
  }
  if (root.getAttribute('xmlns:epub') == null) root.setAttribute('xmlns:epub', epubNs);
  root
    ..setAttribute('lang', lang)
    ..setAttribute('xml:lang', lang);

  // Cabecera: charset, título y la hoja del template, más las hojas propias que no sustituye.
  var head = headOf(doc);
  final keepSheets = [
    for (final link in head == null ? const <XmlElement>[] : elementsOf(head, 'link'))
      if ((link.getAttribute('rel') ?? '').contains('stylesheet') && sheets.contains((link.getAttribute('href') ?? '').replaceFirst(_absolute, ''))) link.getAttribute('href')!,
  ];
  if (head == null) {
    head = _el('head');
    root.children.insert(0, head);
  }
  head.children
    ..clear()
    ..add(XmlText('\n  '))
    ..add(_el('meta', {'charset': 'utf-8'}))
    ..add(XmlText('\n  '))
    ..add(_el('title', {}, [XmlText(d.label)]))
    ..add(XmlText('\n  '));
  for (final href in [styleHref, ...keepSheets]) {
    head.children
      ..add(_el('link', {'href': href, 'rel': 'stylesheet', 'type': 'text/css'}))
      ..add(XmlText('\n  '));
  }
  head.children.last = XmlText('\n');

  final body = bodyOf(doc)!;
  for (final attr in [...body.attributes]) {
    body.removeAttribute(attr.name.qualified);
  }
  setEpubType(body, d.matter.epubType);
  var section = body.childElements.length == 1 && localName(body.childElements.first) == 'section' ? body.childElements.first : null;
  if (section == null) {
    section = _el('section');
    final children = [...body.children];
    for (final c in children) {
      c.remove();
    }
    section.children.addAll(children);
    body.children
      ..add(XmlText('\n  '))
      ..add(section)
      ..add(XmlText('\n'));
  }
  final sectionId = section.getAttribute('id');
  for (final attr in [...section.attributes]) {
    section.removeAttribute(attr.name.qualified);
  }
  if (sectionId != null && referenced.contains('$source#$sectionId')) section.setAttribute('id', sectionId);

  final kind = d.kind;
  if (kind.epubType.isNotEmpty) {
    setEpubType(section, kind.epubType);
    if (kind.role.isNotEmpty) section.setAttribute('role', kind.role);
  }
  var primary = section.descendants.whereType<XmlElement>().where(isHeading).firstOrNull;
  final hiddenHeading = primary == null || headingLabel(primary).isEmpty || classesOf(primary).contains('hidden');
  if (hiddenHeading && !d.inToc) {
    // Un encabezado oculto fuera del índice no cumple ninguna función: la sección se nombra con aria-label.
    if (primary != null && headingLabel(primary).isEmpty || primary != null && classesOf(primary).contains('hidden')) primary.remove();
    section.setAttribute('aria-label', d.label);
  } else {
    if (primary == null) {
      primary = _el('h1', {}, [XmlText(d.label)]);
      setClasses(primary, ['hidden']);
      section.children
        ..insert(0, primary)
        ..insert(0, XmlText('\n    '));
    } else if (headingLabel(primary).isEmpty) {
      primary.children
        ..clear()
        ..add(XmlText(d.label));
      setClasses(primary, [...classesOf(primary), 'hidden']);
    }
    final classes = classesOf(primary).where((c) => c != 'sigil_not_in_toc').toList();
    setClasses(primary, [...classes, if (!d.inToc) 'sigil_not_in_toc']);
    if (colonLabel(primary) case final colon? when colon == d.label) primary.setAttribute('title', colon);
    if (d.inToc && d.label != headingLabel(primary)) {
      if (classesOf(primary).contains('hidden')) {
        primary.children
          ..clear()
          ..add(XmlText(d.label));
        primary.removeAttribute('title');
      } else {
        primary.setAttribute('title', d.label);
      }
    } else if (normalizeSpace(primary.getAttribute('title') ?? '') == headingLabel(primary)) {
      primary.removeAttribute('title');
    }
    final id = primary.getAttribute('id') ?? _headingId;
    primary.setAttribute('id', id);
    section.setAttribute('aria-labelledby', id);
  }
}

// Lo propio de cada tipo, sobre la sección ya completa.
void _finishKind(XmlDocument doc, MigrationDoc d, MigrationProject project) {
  final section = _container(doc);
  switch (d.kind) {
    case MigrationKind.titlePage:
      for (final h2 in elementsOf(section, 'h2')) {
        if (classesOf(h2).contains('subtitle')) h2.setAttribute('role', 'doc-subtitle');
      }
      final block = section.childElements.where((e) => localName(e) == 'div').firstOrNull;
      if (block != null && epubTypeOf(block) == null) setEpubType(block, 'copyright-page');
    case MigrationKind.cover:
      for (final svg in section.descendants.whereType<XmlElement>().where((e) => localName(e) == 'svg').toList()) {
        final image = svg.descendants.whereType<XmlElement>().where((e) => localName(e) == 'image').firstOrNull;
        final href = image?.getAttribute('xlink:href') ?? image?.getAttribute('href');
        if (href == null) continue;
        final figure = _el(
          'figure',
          {'class': 'fill'},
          [
            _el('img', {'src': href, 'alt': 'Cubierta'}),
          ],
        );
        final holder = svg.parent is XmlElement && localName(svg.parent! as XmlElement) == 'div' && (svg.parent! as XmlElement).childElements.length == 1 ? svg.parent! as XmlElement : svg;
        holder.parent!.children[holder.parent!.children.indexOf(holder)] = figure;
      }
      elementsOf(section, 'img').firstOrNull?.setAttribute('role', 'doc-cover');
    case MigrationKind.endnotes:
      _noteList(section);
    case MigrationKind.notice:
      final quote = elementsOf(section, 'blockquote').firstOrNull;
      final block = XmlDocumentFragment.parse(_warningBlock(project)).firstElementChild!.copy();
      if (quote != null) {
        quote.parent!.children[quote.parent!.children.indexOf(quote)] = block;
      } else {
        section.children
          ..add(XmlText('\n    '))
          ..add(block);
      }
    default:
      break;
  }
}

void _dedupeIds(XmlDocument doc) {
  final seen = <String, int>{};
  for (final e in doc.descendants.whereType<XmlElement>()) {
    final id = e.getAttribute('id');
    if (id == null) continue;
    if (RegExp(r'\s').hasMatch(id)) e.setAttribute('id', id.trim().replaceAll(RegExp(r'\s+'), '_'));
    final value = e.getAttribute('id')!;
    seen[value] = (seen[value] ?? 0) + 1;
    if (seen[value]! > 1) e.setAttribute('id', '${value}_${seen[value]}');
  }
}

String _nav(List<_Final> finals, String navPath, String lang, String styleHref, String navStyleHref) {
  final entries = <(int, String, String)>[];
  for (final f in finals) {
    if (f.xml == null) {
      if (f.doc.inToc) entries.add((1, f.path, f.doc.label));
      continue;
    }
    var first = true;
    for (final h in f.xml!.descendants.whereType<XmlElement>().where(isHeading)) {
      final listed = !classesOf(h).contains('sigil_not_in_toc');
      final label = tocLabel(h);
      if (listed && label.isNotEmpty) {
        final level = int.parse(localName(h).substring(1));
        if (first) {
          entries.add((level, f.path, label));
        } else {
          if (h.getAttribute('id') == null) h.setAttribute('id', 'toc-${entries.length + 1}');
          entries.add((level, '${f.path}#${h.getAttribute('id')}', label));
        }
      }
      first = false;
    }
  }
  if (entries.isEmpty && finals.isNotEmpty) entries.add((1, finals.first.path, finals.first.doc.label));
  // Profundidad real: h1 › h4 › h4 quedan en 1, 2, 2.
  final stack = <int>[];
  final levels = [
    for (final (level, _, _) in entries)
      () {
        while (stack.isNotEmpty && stack.last >= level) {
          stack.removeLast();
        }
        stack.add(level);
        return stack.length;
      }(),
  ];
  String href(String target) {
    final hash = target.indexOf('#');
    final path = hash < 0 ? target : target.substring(0, hash);
    return '${relativePath(navPath, path)}${hash < 0 ? '' : target.substring(hash)}';
  }

  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="utf-8"?>')
    ..writeln('<!DOCTYPE html>')
    ..writeln('<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="$lang" xml:lang="$lang">')
    ..writeln('<head>')
    ..writeln('  <meta charset="utf-8"/>')
    ..writeln('  <title>Índice</title>')
    ..writeln('  <link href="$navStyleHref" rel="stylesheet" type="text/css"/>')
    ..writeln('  <link href="$styleHref" rel="stylesheet" type="text/css"/>')
    ..writeln('</head>')
    ..writeln('<body epub:type="frontmatter">')
    ..writeln('  <nav epub:type="toc" id="toc" role="doc-toc">')
    ..writeln('    <h1>Índice de contenido</h1>');
  var depth = 0;
  for (final (i, (_, target, label)) in entries.indexed) {
    final level = levels[i].clamp(1, depth + 1);
    if (level > depth) {
      b.writeln('${'  ' * (2 * level)}<ol>');
    } else {
      b.writeln('${'  ' * (2 * depth + 1)}</li>');
      for (var d = depth; d > level; d--) {
        b
          ..writeln('${'  ' * (2 * d)}</ol>')
          ..writeln('${'  ' * (2 * d - 1)}</li>');
      }
    }
    depth = level;
    b
      ..writeln('${'  ' * (2 * depth + 1)}<li>')
      ..writeln('${'  ' * (2 * depth + 2)}<a href="${escapeXml(href(target))}">${escapeXml(label)}</a>');
  }
  for (var d = depth; d > 0; d--) {
    b
      ..writeln('${'  ' * (2 * d + 1)}</li>')
      ..writeln('${'  ' * (2 * d)}</ol>');
  }
  b.writeln('  </nav>');

  final landmarks = <String, (String, String)>{};
  for (final f in finals) {
    if (f.doc.matter == BookMatter.body) landmarks.putIfAbsent('bodymatter', () => (href(f.path), 'Contenido principal'));
    final type = f.doc.kind.epubType;
    if (type.isNotEmpty && !const {'chapter', 'part', 'notice', 'colophon', 'abstract'}.contains(type)) landmarks.putIfAbsent(type, () => (href(f.path), f.doc.label));
  }
  landmarks.putIfAbsent('toc', () => ('#toc', 'Índice de contenido'));
  b
    ..writeln('  <nav epub:type="landmarks" id="landmarks" hidden="">')
    ..writeln('    <h1>Guías</h1>')
    ..writeln('    <ol>');
  for (final MapEntry(key: type, value: (target, label)) in landmarks.entries) {
    b.writeln('      <li><a epub:type="$type" href="${escapeXml(target)}">${escapeXml(label)}</a></li>');
  }
  b
    ..writeln('    </ol>')
    ..writeln('  </nav>')
    ..writeln('</body>')
    ..writeln('</html>');
  return b.toString();
}

String _opf(EpubArchive archive, MigrationProject project, List<_Final> finals, Map<String, Uint8List> files, String navPath, String lang, DateTime now) {
  final ids = <String>{};
  String idFor(String path) {
    final base = p.posix.basename(path);
    var id = RegExp(r'^[A-Za-z_]').hasMatch(base) ? base : 'x$base';
    for (var n = 2; !ids.add(id); n++) {
      id = '${p.posix.basenameWithoutExtension(base)}_$n${p.posix.extension(base)}';
    }
    return id;
  }

  final coverDoc = finals.where((f) => f.doc.kind == MigrationKind.cover && f.xml != null).firstOrNull;
  final coverSrc = coverDoc == null ? null : elementsOf(coverDoc.xml!, 'img').firstOrNull?.getAttribute('src');
  final coverImage = coverSrc == null ? null : resolvePath(coverDoc!.path, coverSrc);
  // La cubierta y los logos no hacen falta para leer el libro.
  final illustrated = finals.any(
    (f) => f.xml != null && f.doc.kind != MigrationKind.cover && f.doc.kind != MigrationKind.colophon && (elementsOf(f.xml!, 'img').isNotEmpty || elementsOf(f.xml!, 'image').isNotEmpty),
  );
  final docIds = <String, String>{};
  final manifest = StringBuffer();
  String? coverId;
  for (final path in files.keys) {
    if (path == archive.opfPath) continue;
    final id = idFor(path);
    final ext = p.posix.extension(path).replaceFirst('.', '').toLowerCase();
    final declared = archive.byPath(path)?.mediaType ?? _mediaTypes[ext] ?? 'application/octet-stream';
    final type = declared.startsWith('image/') && declared != 'image/svg+xml' ? imageTypeOf(files[path]!) ?? declared : declared;
    final properties = [
      if (path == navPath) 'nav',
      if (path == coverImage) 'cover-image',
      if (type == 'application/xhtml+xml' && path != navPath && utf8.decode(files[path]!, allowMalformed: true).contains('<svg')) 'svg',
    ];
    if (path == coverImage) coverId = id;
    if (type == 'application/xhtml+xml') docIds[path] = id;
    manifest.writeln('    <item id="${escapeXml(id)}" href="${escapeXml(relativePath(archive.opfPath, path))}" media-type="$type"${properties.isEmpty ? '' : ' properties="${properties.join(' ')}"'}/>');
  }
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="utf-8"?>')
    ..writeln('<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="BookId" xml:lang="${escapeXml(lang)}">')
    ..writeln('  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">');
  writeOpfMetadata(b, project.metadata, now: now);
  writeAccessibilityMetadata(b, illustrated: illustrated);
  if (coverId != null) b.writeln('    <meta name="cover" content="${escapeXml(coverId)}"/>');
  b
    ..writeln('  </metadata>')
    ..writeln('  <manifest>')
    ..write(manifest)
    ..writeln('  </manifest>')
    ..writeln('  <spine>');
  for (final f in finals) {
    b.writeln('    <itemref idref="${escapeXml(docIds[f.path]!)}"/>');
  }
  b
    ..writeln('    <itemref idref="${escapeXml(docIds[navPath]!)}" linear="no"/>')
    ..writeln('  </spine>')
    ..writeln('</package>');
  return b.toString();
}

// Figura que ocupaba sola su documento original: es una página de imagen.
XmlElement? _pageFigure(XmlDocument doc) {
  final body = bodyOf(doc);
  if (body == null) return null;
  final figures = elementsOf(body, 'figure').toList();
  if (figures.length != 1) return null;
  final headings = body.descendants.whereType<XmlElement>().where(isHeading).map(textOf).join();
  return textOf(body).replaceAll(headings, '').trim().isEmpty ? figures.first : null;
}

double? _ratio(EpubArchive archive, String docPath, XmlElement figure) {
  final src = elementsOf(figure, 'img').firstOrNull?.getAttribute('src');
  final bytes = src == null ? null : archive.files[resolvePath(docPath, src)];
  if (bytes == null) return null;
  final info = img.findDecoderForData(bytes)?.startDecode(bytes);
  return info == null || info.height == 0 ? null : info.width / info.height;
}

bool _visible(XmlElement e) => !classesOf(e).contains('hidden');

// Una imagen a página completa va sola en su página: salto antes y después si hay
// contenido alrededor. Las muy apaisadas que compartían página con texto no saltan.
void _fillBreaks(XmlDocument doc, String path, EpubArchive archive, Set<XmlElement> pageFigures) {
  for (final figure in elementsOf(doc, 'figure').where((f) => classesOf(f).contains('fill'))) {
    final ratio = _ratio(archive, path, figure);
    if (!pageFigures.contains(figure) && ratio != null && ratio >= 2) {
      setClasses(figure, classesOf(figure).where((c) => c != 'break-before' && c != 'break-after').toList());
      continue;
    }
    final siblings = (figure.parent! as XmlElement).childElements.where(_visible).toList();
    final index = siblings.indexOf(figure);
    setClasses(figure, [...classesOf(figure), if (index > 0) 'break-before', if (index >= 0 && index < siblings.length - 1) 'break-after']);
  }
  // Un salto antes que sigue a un salto después es el mismo salto.
  for (final e in doc.descendants.whereType<XmlElement>().where((e) => classesOf(e).contains('break-before')).toList()) {
    final parent = e.parent;
    if (parent is! XmlElement) continue;
    final siblings = parent.childElements.where(_visible).toList();
    final index = siblings.indexOf(e);
    if (index > 0 && classesOf(siblings[index - 1]).contains('break-after')) setClasses(e, classesOf(e).where((c) => c != 'break-before').toList());
  }
}

const _htmlElements = {'a', 'abbr', 'address', 'area', 'article', 'aside', 'audio', 'b', 'bdi', 'bdo', 'blockquote', 'body', 'br', 'button', 'canvas', 'caption', 'cite', 'code', 'col', 'colgroup', 'data', 'datalist', 'dd', 'del', 'details', 'dfn', 'dialog', 'div', 'dl', 'dt', 'em', 'embed', 'fieldset', 'figcaption', 'figure', 'footer', 'form', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'head', 'header', 'hgroup', 'hr', 'html', 'i', 'iframe', 'img', 'input', 'ins', 'kbd', 'label', 'legend', 'li', 'link', 'main', 'map', 'mark', 'menu', 'meta', 'meter', 'nav', 'noscript', 'object', 'ol', 'optgroup', 'option', 'output', 'p', 'param', 'picture', 'pre', 'progress', 'q', 'rp', 'rt', 'ruby', 's', 'samp', 'script', 'search', 'section', 'select', 'slot', 'small', 'source', 'span', 'strong', 'style', 'sub', 'summary', 'sup', 'table', 'tbody', 'td', 'template', 'textarea', 'tfoot', 'th', 'thead', 'time', 'title', 'tr', 'track', 'u', 'ul', 'var', 'video', 'wbr', 'svg', 'math'};
const _htmlAttributes = {'id', 'class', 'title', 'lang', 'dir', 'style', 'role', 'hidden', 'tabindex', 'accesskey', 'translate', 'href', 'src', 'alt', 'width', 'height', 'colspan', 'rowspan', 'type', 'rel', 'media', 'charset', 'name', 'content', 'http-equiv', 'start', 'reversed', 'value', 'span', 'headers', 'scope', 'abbr', 'cite', 'datetime', 'target', 'download', 'hreflang', 'srcset', 'sizes', 'loading', 'decoding', 'usemap', 'ismap', 'controls', 'poster', 'for', 'label', 'open', 'viewBox', 'version', 'preserveAspectRatio', 'x', 'y', 'd', 'fill', 'stroke', 'transform', 'points', 'cx', 'cy', 'r', 'rx', 'ry', 'x1', 'x2', 'y1', 'y2'};
const _typos = {'o': 'p', 'pp': 'p', 'pa': 'p', 'op': 'p'};
const _inline = {'i', 'b', 'em', 'strong', 'span', 'small', 'a', 'u', 's', 'sup', 'sub', 'font'};
const _blocks = {'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'figure', 'ul', 'ol', 'li', 'dl', 'dt', 'dd', 'table', 'tr', 'aside', 'section'};
const _media = {'img', 'video', 'canvas', 'iframe', 'embed', 'object', 'input', 'source', 'svg', 'image', 'col', 'colgroup'};

void _rename(XmlElement e, String tag) {
  final renamed = XmlElement.tag(tag, attributes: [for (final a in e.attributes) a.copy()], isSelfClosing: e.isSelfClosing);
  final children = [...e.children];
  for (final c in children) {
    c.remove();
  }
  renamed.children.addAll(children);
  e.parent!.children[e.parent!.children.indexOf(e)] = renamed;
}

// Parecido entre dos nombres (0–1) por distancia de edición.
double _similarity(String a, String b) {
  final d = List.generate(a.length + 1, (i) => List.filled(b.length + 1, 0));
  for (var i = 0; i <= a.length; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j <= b.length; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      d[i][j] = [d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)].reduce((x, y) => x < y ? x : y);
    }
  }
  return 1 - d[a.length][b.length] / [a.length, b.length].reduce((x, y) => x > y ? x : y);
}

// Lo que no es HTML válido en el cuerpo: etiquetas y atributos que no existen,
// elementos de línea sin cerrar alrededor de bloques, listas y tablas mal formadas.
void _fixHtml(XmlElement body, void Function(String message) note) {
  for (final e in body.descendants.whereType<XmlElement>().toList()) {
    final name = localName(e);
    if (e.name.prefix != null || _htmlElements.contains(name) || e.ancestors.whereType<XmlElement>().any((a) => const {'svg', 'math'}.contains(localName(a)))) continue;
    final close = _htmlElements.map((t) => (t, _similarity(name, t))).where((x) => x.$2 >= 0.75).fold<(String, double)?>(null, (best, x) => best == null || x.$2 > best.$2 ? x : best);
    final parent = e.parent;
    final fixed = _typos[name] ?? close?.$1 ?? (parent is XmlElement && const {'section', 'div', 'blockquote', 'body', 'aside', 'figure'}.contains(localName(parent)) ? 'p' : 'span');
    _rename(e, fixed);
    note('Etiqueta <$name> cambiada por <$fixed>.');
  }
  for (final e in body.descendants.whereType<XmlElement>()) {
    final media = _media.contains(localName(e));
    for (final attr in [...e.attributes]) {
      final name = attr.name.qualified;
      if (name.contains(':') || name.startsWith('data-') || name.startsWith('aria-')) continue;
      final remove = switch (name) {
        'alt' => !const {'img', 'area', 'input', 'image'}.contains(localName(e)),
        'width' || 'height' => !media || !RegExp(r'^\d+$').hasMatch(attr.value.trim()),
        'colspan' || 'rowspan' || 'span' => !RegExp(r'^\d+$').hasMatch(attr.value.trim()),
        _ => !_htmlAttributes.contains(name),
      };
      if (remove) {
        e.removeAttribute(name);
        note('Atributo $name quitado de <${localName(e)}>.');
      }
    }
  }
  // Elemento de línea sin cerrar que acabó envolviendo bloques: se desenvuelve.
  for (final e in body.descendants.whereType<XmlElement>().toList()) {
    if (!_inline.contains(localName(e)) || e.parent == null || !e.childElements.any((c) => _blocks.contains(localName(c)))) continue;
    if (e.children.whereType<XmlText>().any((t) => t.value.trim().isNotEmpty)) continue;
    _unwrap(e);
    note('<${localName(e)}> sin cerrar alrededor de bloques.');
  }
  // Una lista solo contiene <li>.
  for (final list in body.descendants.whereType<XmlElement>().where((e) => localName(e) == 'ul' || localName(e) == 'ol').toList()) {
    for (final child in [...list.children]) {
      if (child is XmlElement && const {'li', 'script', 'template'}.contains(localName(child))) continue;
      if (child is XmlText && child.value.trim().isEmpty || child is XmlComment) continue;
      final li = _el('li');
      list.children[list.children.indexOf(child)] = li;
      li.children.add(child is XmlText ? XmlText(child.value.trim()) : child);
      note('Contenido suelto en una lista metido en <li>.');
    }
  }
  // <p><p>…</p></p>: el exterior sobra.
  for (final outer in elementsOf(body, 'p').toList()) {
    final inner = outer.childElements.toList();
    if (outer.parent == null || inner.length != 1 || localName(inner.first) != 'p' || outer.children.whereType<XmlText>().any((t) => t.value.trim().isNotEmpty)) continue;
    _unwrap(outer);
    note('Párrafo dentro de otro párrafo.');
  }
  // Celdas sueltas dentro de una tabla van en una fila.
  for (final group in body.descendants.whereType<XmlElement>().where((e) => const {'table', 'thead', 'tbody', 'tfoot'}.contains(localName(e))).toList()) {
    XmlElement? row;
    for (final child in [...group.children]) {
      if (child is XmlElement && const {'td', 'th'}.contains(localName(child))) {
        if (row == null) {
          row = _el('tr');
          group.children.insert(group.children.indexOf(child), row);
          note('Celdas de tabla sin fila.');
        }
        child.remove();
        row.children.add(child);
      } else if (child is XmlElement) {
        row = null;
      }
    }
  }
  // Celdas y filas fuera de una tabla son bloques.
  for (final cell in body.descendants.whereType<XmlElement>().where((e) => const {'td', 'th', 'tr', 'tbody', 'thead', 'tfoot'}.contains(localName(e))).toList()) {
    if (cell.ancestors.whereType<XmlElement>().any((a) => localName(a) == 'table')) continue;
    _rename(cell, 'div');
    note('Celda de tabla fuera de una tabla.');
  }
}
