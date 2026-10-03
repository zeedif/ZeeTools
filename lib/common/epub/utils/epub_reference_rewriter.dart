import 'epub_path_utils.dart';

// Reescribe las referencias a un recurso renombrado en atributos, srcset y url() de CSS.
abstract final class EpubReferenceRewriter {
  static final _attribute = RegExp(r'''(\s(?:xlink:href|href|src|poster|data|altimg|longdesc)\s*=\s*)(["'])(.*?)\2''', dotAll: true);
  static final _srcset = RegExp(r'''(\ssrcset\s*=\s*)(["'])(.*?)\2''', dotAll: true);
  static final _cssUrl = RegExp(r'''(url\(\s*)(["']?)([^"')]+?)\2(\s*\))''');
  static final _scheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:');

  // [fileDir]: directorio del documento con / final; [oldPath]: ruta del recurso en el contenedor.
  // Devuelve null si el documento no referencia [oldPath].
  static String? rewrite(String content, {required String fileDir, required String oldPath, required String Function(String segment) renameSegment}) {
    var changed = false;

    String value(String raw) {
      final replaced = _replaceValue(raw, fileDir: fileDir, oldPath: oldPath, renameSegment: renameSegment);
      if (replaced == null) return raw;
      changed = true;
      return replaced;
    }

    var result = content.replaceAllMapped(_attribute, (m) => '${m[1]}${m[2]}${value(m[3]!)}${m[2]}');
    result = result.replaceAllMapped(_srcset, (m) {
      final candidates = m[3]!
          .split(',')
          .map((candidate) {
            final trimmed = candidate.trim();
            if (trimmed.isEmpty) return candidate;
            final space = trimmed.indexOf(RegExp(r'\s'));
            if (space < 0) return candidate.replaceFirst(trimmed, value(trimmed));
            return candidate.replaceFirst(trimmed, '${value(trimmed.substring(0, space))}${trimmed.substring(space)}');
          })
          .join(',');
      return '${m[1]}${m[2]}$candidates${m[2]}';
    });
    result = result.replaceAllMapped(_cssUrl, (m) => '${m[1]}${m[2]}${value(m[3]!)}${m[2]}${m[4]}');
    return changed ? result : null;
  }

  static String? _replaceValue(String raw, {required String fileDir, required String oldPath, required String Function(String segment) renameSegment}) {
    final url = raw.trim();
    if (url.isEmpty || url.startsWith('#') || _scheme.hasMatch(url)) return null;

    final cut = url.indexOf(RegExp(r'[?#]'));
    final pathPart = cut < 0 ? url : url.substring(0, cut);
    final suffix = cut < 0 ? '' : url.substring(cut);
    try {
      if (EpubPathUtils.resolve(fileDir, pathPart.replaceAll('&amp;', '&')) != oldPath) return null;
    } on FormatException {
      return null;
    }
    return '${EpubPathUtils.renameLastSegment(pathPart, renameSegment)}$suffix';
  }
}
