abstract final class EpubPathUtils {
  static String resolve(String opfBasePath, String href) {
    final base = Uri.parse(
      opfBasePath.endsWith('/') ? opfBasePath : '$opfBasePath/',
    );
    return Uri.decodeFull(base.resolve(href).path).replaceAll(RegExp(r'^/'), '');
  }

  static String parentDir(String filePath) {
    final lastSlash = filePath.lastIndexOf('/');
    return lastSlash < 0 ? '' : filePath.substring(0, lastSlash + 1);
  }

  // Aplica [rename] al último segmento de [path].
  static String renameLastSegment(String path, String Function(String segment) rename) {
    final lastSlash = path.lastIndexOf('/');
    return '${path.substring(0, lastSlash + 1)}${rename(path.substring(lastSlash + 1))}';
  }

  static String withExtension(String fileName, String extension, {String suffix = ''}) {
    final dot = fileName.lastIndexOf('.');
    final stem = dot <= 0 ? fileName : fileName.substring(0, dot);
    return '$stem$suffix.$extension';
  }
}
