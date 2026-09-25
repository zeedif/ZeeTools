enum EpubFileKind {
  xhtml,
  css,
  javascript,
  xml, // dialectos XML como opf, ncx, smil, dtbook
  svg,
  other;

  static EpubFileKind fromMediaType(String mediaType) {
    final t = mediaType.split(';').first.trim().toLowerCase();
    if (t.contains('html')) return EpubFileKind.xhtml;
    if (t.contains('css')) return EpubFileKind.css;
    if (t.contains('svg')) return EpubFileKind.svg;
    if (t.contains('script') || t.contains('javascript')) return EpubFileKind.javascript;
    if (t.contains('xml')) return EpubFileKind.xml;
    return EpubFileKind.other;
  }
}
