import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/presentation/views/dashboard_view.dart';
import '../../features/home/presentation/views/layout_view.dart';
import '../../features/settings/presentation/views/settings_view.dart';
import 'routes.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: Routes.dashboard,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return LayoutView(navigationShell: navigationShell);
      },
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.dashboard,
              builder: (context, state) => const DashboardView(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.settings,
              builder: (context, state) => const SettingsView(),
            ),
          ],
        ),
      ],
    ),
  ],
);
