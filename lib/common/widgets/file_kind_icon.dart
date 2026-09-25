import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../epub/utils/epub_file_kind.dart';

extension EpubFileKindVisuals on EpubFileKind {
  String get assetPath => switch (this) {
    EpubFileKind.xhtml => 'assets/icons/html.svg',
    EpubFileKind.css => 'assets/icons/css.svg',
    EpubFileKind.javascript => 'assets/icons/javascript.svg',
    EpubFileKind.xml => 'assets/icons/xml.svg',
    EpubFileKind.svg => 'assets/icons/svg.svg',
    EpubFileKind.other => 'assets/icons/document.svg',
  };
}

// Icono SVG por tipo de archivo. `selected` distingue si el archivo está
// activo (color propio del logo) o no (gris, como un checkbox sin marcar).
class FileKindIcon extends StatelessWidget {
  const FileKindIcon({super.key, required this.kind, this.selected = true, this.size = 20});

  final EpubFileKind kind;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      kind.assetPath,
      width: size,
      height: size,
      colorFilter: selected ? null : ColorFilter.mode(Theme.of(context).colorScheme.outline, BlendMode.srcIn),
    );
  }
}
