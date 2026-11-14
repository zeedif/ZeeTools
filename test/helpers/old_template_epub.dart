import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

final testPng = Uint8List.fromList(base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='));

String _page(String title, String body, {String matter = 'bodymatter'}) => '''<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="es" xml:lang="es">
<head>
  <title>$title</title>
  <link rel="stylesheet" type="text/css" href="../Styles/style.css"/>
</head>
<body epub:type="$matter">
$body
</body>
</html>
''';

// EPUB con la forma del template anterior: capítulo partido en dos archivos, notas y clases antiguas.
Uint8List oldTemplateEpub({String? styleCss}) {
  final files = <String, String>{
    'META-INF/container.xml': '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
    'OEBPS/content.opf': '''<?xml version="1.0" encoding="utf-8"?>
<package version="3.0" unique-identifier="BookId" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:identifier id="BookId">urn:uuid:5eee6da9-9951-4726-84a9-38383b22d39d</dc:identifier>
    <dc:title>Mi novela - Volumen 01 [MN]</dc:title>
    <dc:language>es</dc:language>
    <dc:date>2017-25-03T00:00:00Z</dc:date>
    <dc:identifier opf:scheme="ISBN">urn:isbn:9784046850881</dc:identifier>
  </metadata>
  <manifest>
    <item id="cubierta" href="Text/cubierta.xhtml" media-type="application/xhtml+xml"/>
    <item id="s1" href="Text/Section0001-1.xhtml" media-type="application/xhtml+xml"/>
    <item id="s2" href="Text/Section0001-2.xhtml" media-type="application/xhtml+xml"/>
    <item id="notas" href="Text/notas.xhtml" media-type="application/xhtml+xml"/>
    <item id="toc" href="Text/toc.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="style" href="Styles/style.css" media-type="text/css"/>
    <item id="cover" href="Images/cover.png" media-type="image/jpeg"/>
  </manifest>
  <spine>
    <itemref idref="cubierta"/><itemref idref="s1"/><itemref idref="s2"/><itemref idref="notas"/><itemref idref="toc"/>
  </spine>
</package>''',
    'OEBPS/Text/cubierta.xhtml': _page('Cubierta', '<h1 class="oculto" title="Cubierta"></h1>\n<figure class="dimg" epub:type="cover"><img role="doc-cover" src="../Images/cover.png" alt="Cubierta"/></figure>', matter: 'frontmatter'),
    'OEBPS/Text/Section0001-1.xhtml': _page('Capítulo 1', '<section epub:type="chapter" id="chapter">\n<h1 class="oculto" title="Capítulo 1: El inicio"></h1>\n<figure class="dimg"><img src="../Images/cover.png" alt=""/></figure>\n</section>'),
    'OEBPS/Text/Section0001-2.xhtml': _page('Capítulo 1', '<section epub:type="chapter">\n<header><h1 class="sigil_not_in_toc">Capítulo 1<br/><small>El inicio</small></h1></header>\n<p class="centrado salto1 carta">Texto<a href="notas.xhtml#nt1" id="rf1"><sup>1</sup></a>.</p>\n<p><big>Grande</big> y <atrong>error</atrong>.</p>\n</section>'),
    'OEBPS/Text/notas.xhtml': _page('Notas', '<section epub:type="rearnotes">\n<header><h2 class="sigil_not_in_toc">Notas</h2></header>\n<div class="nota"><p><a id="nt1" href="Section0001-2.xhtml#rf1"><sup>1</sup> Una nota.</a></p></div>\n</section>', matter: 'backmatter'),
    'OEBPS/Text/toc.xhtml': _page('Índice', '<nav epub:type="toc" id="toc"><ol><li><a href="cubierta.xhtml">Cubierta</a></li><li><a href="Section0001-1.xhtml">Capítulo 1: El inicio</a></li></ol></nav>'),
    'OEBPS/Styles/style.css': styleCss ?? '.centrado { text-align: center; }\n.dimg { width: 100%; }\n/* Fin del CSS */\n.carta { font-style: italic; }\n',
  };
  final zip = Archive()..addFile(ArchiveFile.noCompress('mimetype', 20, utf8.encode('application/epub+zip')));
  for (final MapEntry(key: path, value: text) in files.entries) {
    final bytes = utf8.encode(text);
    zip.addFile(ArchiveFile(path, bytes.length, bytes));
  }
  zip.addFile(ArchiveFile('OEBPS/Images/cover.png', testPng.length, testPng));
  return ZipEncoder().encodeBytes(zip);
}
