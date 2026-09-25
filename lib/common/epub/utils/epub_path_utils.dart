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
}
