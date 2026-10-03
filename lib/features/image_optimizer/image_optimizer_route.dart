import 'package:go_router/go_router.dart';

import 'presentation/views/image_optimizer_view.dart';

abstract final class ImageOptimizerRoute {
  static const name = 'image-optimizer';
  static const path = 'image-optimizer';

  static GoRoute get route => GoRoute(
    name: name,
    path: path,
    builder: (_, _) => const ImageOptimizerView(),
  );
}
