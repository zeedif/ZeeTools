import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '/features/settings/presentation/cubit/settings_cubit.dart';
import '/inject_dependencies.dart';
import 'data/plugin_registry.dart';

abstract final class PluginsRoute {
  static const name = 'plugin';
  static const path = 'plugin/:id';

  static GoRoute get route => GoRoute(
    name: name,
    path: path,
    // Un complemento que no existe o está desactivado vuelve al dashboard.
    redirect: (context, state) {
      final id = state.pathParameters['id']!;
      final available = getIt<PluginRegistry>()[id] != null && !context.read<SettingsCubit>().state.preferences.disabledPlugins.contains(id);
      return available ? null : '/';
    },
    builder: (context, state) => getIt<PluginRegistry>()[state.pathParameters['id']!]!.build(context),
  );
}
