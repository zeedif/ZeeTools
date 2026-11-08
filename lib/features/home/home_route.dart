import 'package:go_router/go_router.dart';

import '/features/epub_migrator/epub_migrator_route.dart';
import '/features/epub_templater/epub_templater_route.dart';
import '/features/image_optimizer/image_optimizer_route.dart';
import '/features/metadata_editor/metadata_editor_route.dart';
import '/features/search_replace/search_replace_route.dart';
import '/features/plugins/plugins_route.dart';
import 'presentation/views/dashboard_view.dart';

abstract final class HomeRoute {
  static const name = 'dashboard';
  static const path = '/';

  static GoRoute get route => GoRoute(
    name: name,
    path: path,
    builder: (_, _) => const DashboardView(),
    routes: [
      SearchReplaceRoute.route,
      ImageOptimizerRoute.route,
      EpubTemplaterRoute.route,
      MetadataEditorRoute.route,
      EpubMigratorRoute.route,
      PluginsRoute.route,
    ],
  );
}
