import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// SVG que toma color y tamaño de [IconTheme] cuando no se pasan explícitos,
// igual que [Icon].
class SvgIcon extends StatelessWidget {
  const SvgIcon(this.asset, {super.key, this.size, this.color});

  final String asset;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final resolvedSize = size ?? iconTheme.size;
    final resolvedColor = color ?? iconTheme.color;
    return SvgPicture.asset(
      asset,
      width: resolvedSize,
      height: resolvedSize,
      colorFilter: resolvedColor == null ? null : ColorFilter.mode(resolvedColor, BlendMode.srcIn),
    );
  }
}
