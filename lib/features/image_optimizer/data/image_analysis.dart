import 'dart:typed_data';

import 'package:image/image.dart' as img;

class ImageAnalysis {
  const ImageAnalysis({
    required this.width,
    required this.height,
    required this.animated,
    this.hasAlpha = false,
    this.alphaRemoved = false,
    this.orientationBaked = false,
    this.keepsIcc = false,
    this.referencePng,
    this.referencePnm,
  });

  final int width;
  final int height;
  final bool animated;
  final bool hasAlpha;
  // Tenía canal alfa con todos sus píxeles opacos.
  final bool alphaRemoved;
  final bool orientationBaked;
  // Perfil ICC distinto de sRGB conservado en la referencia.
  final bool keepsIcc;
  // Píxeles a 8 bits (gris, gris+alfa, RGB o RGBA) sin metadatos salvo el ICC conservado.
  final Uint8List? referencePng;
  // PPM/PGM para cjpeg; solo sin alfa.
  final Uint8List? referencePnm;
}

ImageAnalysis analyzeImage(Uint8List bytes) {
  final decoder = img.findDecoderForData(bytes);
  if (decoder == null) throw const FormatException('El decodificador no reconoce la imagen');
  final info = decoder.startDecode(bytes);
  if (info == null) throw const FormatException('No se pudo leer la imagen');
  if (info.numFrames > 1) return ImageAnalysis(width: info.width, height: info.height, animated: true);

  var image = decoder.decode(bytes, frame: 0);
  if (image == null) throw const FormatException('No se pudo decodificar la imagen');

  final orientationBaked = (image.exif.imageIfd.orientation ?? 1) != 1;
  if (orientationBaked) image = img.bakeOrientation(image);

  // Sin parámetro alpha: convert() lo aplicaría sobre el alfa existente.
  final rgba = image.convert(format: img.Format.uint8, numChannels: 4).getBytes(order: img.ChannelOrder.rgba);
  var alphaUsed = false;
  var gray = true;
  for (var i = 0; i < rgba.length; i += 4) {
    if (!alphaUsed && rgba[i + 3] != 255) alphaUsed = true;
    if (gray && (rgba[i] != rgba[i + 1] || rgba[i + 1] != rgba[i + 2])) gray = false;
    if (alphaUsed && !gray) break;
  }

  final icc = image.iccProfile;
  final keepsIcc = icc != null && !_isSrgbProfile(icc.decompressed());
  final channels = (gray ? 1 : 3) + (alphaUsed ? 1 : 0);
  final pixels = channels == 4 ? rgba : _pack(rgba, gray: gray, alpha: alphaUsed);

  return ImageAnalysis(
    width: image.width,
    height: image.height,
    animated: false,
    hasAlpha: alphaUsed,
    alphaRemoved: image.hasAlpha && !alphaUsed,
    orientationBaked: orientationBaked,
    keepsIcc: keepsIcc,
    referencePng: img.encodePng(
      img.Image.fromBytes(width: image.width, height: image.height, bytes: pixels.buffer, numChannels: channels, iccp: keepsIcc ? icc : null),
      level: 1,
    ),
    referencePnm: alphaUsed ? null : _pnm(pixels, image.width, image.height, gray: gray),
  );
}

Uint8List _pack(Uint8List rgba, {required bool gray, required bool alpha}) {
  final out = Uint8List(rgba.length ~/ 4 * ((gray ? 1 : 3) + (alpha ? 1 : 0)));
  var o = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if (gray) {
      out[o++] = rgba[i];
    } else {
      out[o++] = rgba[i];
      out[o++] = rgba[i + 1];
      out[o++] = rgba[i + 2];
    }
    if (alpha) out[o++] = rgba[i + 3];
  }
  return out;
}

Uint8List _pnm(Uint8List pixels, int width, int height, {required bool gray}) {
  final header = '${gray ? 'P5' : 'P6'}\n$width $height\n255\n'.codeUnits;
  return Uint8List(header.length + pixels.length)
    ..setAll(0, header)
    ..setAll(header.length, pixels);
}

// Busca 'sRGB' en la etiqueta 'desc' (ASCII en ICC v2, UTF-16BE en v4).
bool _isSrgbProfile(Uint8List icc) {
  if (icc.length < 132) return false;
  final data = ByteData.sublistView(icc);
  for (var i = 0; i < data.getUint32(128); i++) {
    final entry = 132 + i * 12;
    if (entry + 12 > icc.length) break;
    if (String.fromCharCodes(icc.sublist(entry, entry + 4)) != 'desc') continue;
    final offset = data.getUint32(entry + 4);
    final end = offset + data.getUint32(entry + 8);
    if (end > icc.length) return false;
    return String.fromCharCodes(icc.sublist(offset, end).where((c) => c >= 32 && c < 127)).contains('sRGB');
  }
  return false;
}
