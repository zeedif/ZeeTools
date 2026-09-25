import 'package:go_router/go_router.dart';

import '/features/search_replace/search_replace_route.dart';
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
    ],
  );
}
