import 'dart:typed_data';

enum ImageFormat {
  jpeg('JPEG', 'image/jpeg', 'jpg'),
  png('PNG', 'image/png', 'png'),
  webp('WebP', 'image/webp', 'webp'),
  avif('AVIF', 'image/avif', 'avif'),
  jxl('JPEG XL', 'image/jxl', 'jxl'),
  gif('GIF', 'image/gif', 'gif'),
  bmp('BMP', 'image/bmp', 'bmp'),
  tiff('TIFF', 'image/tiff', 'tif');

  const ImageFormat(this.label, this.mediaType, this.extension);

  final String label;
  final String mediaType;
  final String extension;

  static const outputs = [jpeg, png, webp, avif, jxl];
  static const defaultOutputs = [jpeg, png, webp];

  static const inputExtensions = ['jpg', 'jpeg', 'jpe', 'jfif', 'png', 'webp', 'avif', 'jxl', 'gif', 'bmp', 'tif', 'tiff'];

  bool get isOutput => outputs.contains(this);

  bool get supportsAlpha => this != jpeg;

  static ImageFormat? fromMediaType(String mediaType) {
    final base = mediaType.split(';').first.trim().toLowerCase();
    for (final f in values) {
      if (f.mediaType == base) return f;
    }
    return null;
  }

  static ImageFormat? detect(Uint8List b) {
    bool at(int offset, List<int> sig) {
      if (b.length < offset + sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (b[offset + i] != sig[i]) return false;
      }
      return true;
    }

    if (at(0, const [0xFF, 0xD8, 0xFF])) return jpeg;
    if (at(0, const [0x89, 0x50, 0x4E, 0x47])) return png;
    if (at(0, 'GIF8'.codeUnits)) return gif;
    if (at(0, 'RIFF'.codeUnits) && at(8, 'WEBP'.codeUnits)) return webp;
    if (at(4, 'ftyp'.codeUnits) && (at(8, 'avif'.codeUnits) || at(8, 'avis'.codeUnits))) return avif;
    if (at(0, const [0xFF, 0x0A]) || at(0, const [0x00, 0x00, 0x00, 0x0C, 0x4A, 0x58, 0x4C, 0x20])) return jxl;
    if (at(0, 'BM'.codeUnits)) return bmp;
    if (at(0, const [0x49, 0x49, 0x2A, 0x00]) || at(0, const [0x4D, 0x4D, 0x00, 0x2A])) return tiff;
    return null;
  }
}

bool isLosslessEncoding(ImageFormat format, Uint8List bytes) => switch (format) {
  ImageFormat.png || ImageFormat.gif || ImageFormat.bmp || ImageFormat.tiff => true,
  ImageFormat.webp => !_riffChunks(bytes).contains('VP8 '),
  _ => false,
};

bool isAnimatedContainer(ImageFormat format, Uint8List bytes) => switch (format) {
  ImageFormat.webp => _riffChunks(bytes).contains('ANIM'),
  ImageFormat.avif => bytes.length >= 12 && String.fromCharCodes(bytes.sublist(8, 12)) == 'avis',
  _ => false,
};

Set<String> _riffChunks(Uint8List b) {
  final chunks = <String>{};
  var pos = 12;
  while (pos + 8 <= b.length) {
    chunks.add(String.fromCharCodes(b.sublist(pos, pos + 4)));
    final size = b[pos + 4] | b[pos + 5] << 8 | b[pos + 6] << 16 | b[pos + 7] << 24;
    pos += 8 + size + (size & 1);
  }
  return chunks;
}
