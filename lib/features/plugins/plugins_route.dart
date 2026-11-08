import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '/inject_dependencies.dart';
import 'data/plugin_registry.dart';
import 'presentation/cubit/plugins_cubit.dart';
import 'presentation/cubit/plugins_state.dart';
import 'presentation/views/plugin_error_boundary.dart';

abstract final class PluginsRoute {
  static const name = 'plugin_view';
  static const path = 'plugin/:id';

  static GoRoute get route => GoRoute(
        name: name,
        path: path,
        builder: (context, state) {
          final pluginId = state.pathParameters['id'] ?? '';
          return BlocBuilder<PluginsCubit, PluginsState>(
            builder: (context, pluginsState) {
              final plugin = pluginsState.plugins.where((p) => p.id == pluginId).firstOrNull;
              if (plugin == null) {
                return Scaffold(
                  appBar: AppBar(title: const Text('Complemento no encontrado')),
                  body: const Center(child: Text('No se encontró el complemento solicitado.')),
                );
              }

              final registry = getIt<PluginRegistry>();
              final nativeExt = registry.get(plugin.id);

              final Widget child;
              if (nativeExt != null) {
                child = nativeExt.buildView(context, plugin);
              } else {
                child = Scaffold(
                  appBar: AppBar(title: Text(plugin.name)),
                  body: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(plugin.iconData, size: 64, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(height: 16),
                          Text(plugin.name, style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 8),
                          Text(plugin.description, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          Text(
                            'Ubicación: ${plugin.directoryPath}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return PluginErrorBoundary(
                pluginName: plugin.name,
                child: child,
              );
            },
          );
        },
      );
}
