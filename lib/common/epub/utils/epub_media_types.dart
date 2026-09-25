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

  static bool isTextType(String mediaType) {
    final base = mediaType.split(';').first.trim().toLowerCase();
    return _textTypes.contains(base);
  }
}
