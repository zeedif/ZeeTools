import 'package:go_router/go_router.dart';

import 'presentation/views/settings_view.dart';

abstract final class SettingsRoute {
  static const name = 'settings';
  static const path = '/settings';

  static GoRoute get route => GoRoute(
    name: name,
    path: path,
    builder: (_, _) => const SettingsView(),
  );
}
