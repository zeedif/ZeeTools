import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '/features/home/home_route.dart';
import '/features/settings/settings_route.dart';
import 'app_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(navigationShell: shell),
      branches: [
        StatefulShellBranch(routes: [HomeRoute.route]),
        StatefulShellBranch(routes: [SettingsRoute.route]),
      ],
    ),
  ],
);
