class NativeToolPackage {
  const NativeToolPackage(this.name, this.windowsUrl);

  final String name;
  final String windowsUrl;
}

const _libjxl = NativeToolPackage('libjxl 0.11.2', 'https://github.com/libjxl/libjxl/releases/download/v0.11.2/jxl-x64-windows-static.zip');
const _libwebp = NativeToolPackage('libwebp 1.6.0', 'https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0-windows-x64.zip');
const _libavif = NativeToolPackage('libavif 1.4.2', 'https://github.com/AOMediaCodec/libavif/releases/download/v1.4.2/windows-artifacts.zip');
const _oxipng = NativeToolPackage('oxipng 10.2.1', 'https://github.com/oxipng/oxipng/releases/download/v10.2.1/oxipng-10.2.1-x86_64-pc-windows-msvc.zip');
const _mozjpeg = NativeToolPackage('mozjpeg 4.1.5', 'https://github.com/garyzyg/mozjpeg-windows/releases/download/4.1.5/mozjpeg-x64.zip');

// En Windows se descargan de [windowsPackage]; en Linux y macOS se buscan en el PATH por [command].
enum NativeTool {
  cjpegli('cjpegli', _libjxl, 'bin/cjpegli.exe'),
  cjxl('cjxl', _libjxl, 'bin/cjxl.exe'),
  djxl('djxl', _libjxl, 'bin/djxl.exe'),
  ssimulacra2('ssimulacra2', _libjxl, 'bin/ssimulacra2.exe'),
  cwebp('cwebp', _libwebp, 'bin/cwebp.exe'),
  dwebp('dwebp', _libwebp, 'bin/dwebp.exe'),
  avifenc('avifenc', _libavif, 'avifenc.exe'),
  avifdec('avifdec', _libavif, 'avifdec.exe'),
  oxipng('oxipng', _oxipng, 'oxipng.exe'),
  jpegtran('jpegtran', _mozjpeg, 'jpegtran-static.exe'),
  mozjpeg('cjpeg', _mozjpeg, 'cjpeg-static.exe');

  const NativeTool(this.command, this.windowsPackage, this.windowsMember);

  final String command;
  final NativeToolPackage windowsPackage;
  // Sufijo de la ruta del ejecutable dentro del zip.
  final String windowsMember;

  String get windowsFileName => windowsMember.split('/').last;
}
