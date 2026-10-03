abstract final class EpubMediaTypes {
  static const Set<String> _textTypes = {
    'application/xhtml+xml',
    'text/html',
    'text/css',
    'text/javascript',
    'application/javascript',
    'application/x-javascript',
    'image/svg+xml',
    'application/x-dtbncx+xml',
    'application/x-dtbook+xml',
    'application/smil+xml',
    'application/oebps-package+xml',
    'text/plain',
  };

  // Imágenes ráster core de EPUB 3.4.
  static const Set<String> _rasterImageTypes = {
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp',
    'image/avif',
    'image/jxl',
  };

  static bool isTextType(String mediaType) {
    final base = mediaType.split(';').first.trim().toLowerCase();
    return _textTypes.contains(base);
  }

  static bool isRasterImageType(String mediaType) {
    final base = mediaType.split(';').first.trim().toLowerCase();
    return _rasterImageTypes.contains(base);
  }
}
