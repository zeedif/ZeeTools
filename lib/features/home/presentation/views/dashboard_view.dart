import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '/features/epub_migrator/epub_migrator_route.dart';
import '/features/epub_templater/epub_templater_route.dart';
import '/features/image_optimizer/image_optimizer_route.dart';
import '/features/metadata_editor/metadata_editor_route.dart';
import '/features/plugins/data/plugin_registry.dart';
import '/features/plugins/plugins_route.dart';
import '/features/search_replace/search_replace_route.dart';
import '/features/settings/presentation/cubit/settings_cubit.dart';
import '/inject_dependencies.dart';

class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final disabled = context.select((SettingsCubit c) => c.state.preferences.disabledPlugins);
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: GridView.count(
        crossAxisCount: 3,
        padding: const EdgeInsets.all(16),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        children: [
          _ToolCard(icon: Icons.find_replace_rounded, label: 'Búsqueda y Reemplazo', onTap: () => context.goNamed(SearchReplaceRoute.name)),
          _ToolCard(icon: Icons.photo_size_select_large_rounded, label: 'Optimizador de Imágenes', onTap: () => context.goNamed(ImageOptimizerRoute.name)),
          _ToolCard(icon: Icons.library_books_outlined, label: 'Plantillas EPUB', onTap: () => context.goNamed(EpubTemplaterRoute.name)),
          _ToolCard(icon: Icons.edit_note_outlined, label: 'Editor de metadatos', onTap: () => context.goNamed(MetadataEditorRoute.name)),
          _ToolCard(icon: Icons.auto_fix_high_outlined, label: 'Migrar al template nuevo', onTap: () => context.goNamed(EpubMigratorRoute.name)),
          for (final plugin in getIt<PluginRegistry>().all)
            if (!disabled.contains(plugin.id))
              _ToolCard(icon: plugin.icon, label: plugin.name, onTap: () => context.goNamed(PluginsRoute.name, pathParameters: {'id': plugin.id})),
        ],
      ),
    );
  }
}

class const _ToolCard({required final IconData icon, required final String label, required final VoidCallback onTap}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 36),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
