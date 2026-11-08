import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '/common/widgets/form_section.dart';
import '../../domain/plugin_manifest.dart';
import '../cubit/plugins_cubit.dart';
import '../cubit/plugins_state.dart';
import 'plugin_details_dialog.dart';

class PluginsSettingsSection extends StatelessWidget {
  const PluginsSettingsSection({super.key});

  Future<void> _pickAndInstallZip(BuildContext context) async {
    final path = (await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      dialogTitle: 'Selecciona un complemento (.zip)',
      windowsOptions: const WindowsOptions(lockParentWindow: true),
    )).map((f) => f.path).whereType<String>().firstOrNull;

    if (path != null && context.mounted) {
      context.read<PluginsCubit>().installFromZip(path);
    }
  }

  void _confirmUninstall(BuildContext context, PluginManifest plugin) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Desinstalar complemento?'),
        content: Text(
          '¿Seguro que deseas eliminar el complemento "${plugin.name}"? Se borrarán sus archivos locales.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              context.read<PluginsCubit>().uninstallPlugin(
                    plugin.id,
                    plugin.directoryPath,
                  );
            },
            child: const Text('Desinstalar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return BlocConsumer<PluginsCubit, PluginsState>(
      listener: (context, state) {
        if (state.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage!),
              backgroundColor: cs.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        if (state.successMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.successMessage!),
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      builder: (context, state) {
        final cubit = context.read<PluginsCubit>();
        final total = state.plugins.length;
        final enabledCount = state.enabledPlugins.length;

        return FormSection(
          title: 'Complementos',
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    total == 0
                        ? 'Extiende ZeeTools instalando complementos (.zip).'
                        : '$total complemento${total > 1 ? 's' : ''} instalado${total > 1 ? 's' : ''} ($enabledCount activo${enabledCount != 1 ? 's' : ''})',
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.archive_outlined, size: 18),
                  label: const Text('Instalar (.zip)'),
                  onPressed: () => _pickAndInstallZip(context),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: const Text('Carpeta'),
                  onPressed: cubit.openFolder,
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Recargar complementos',
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  onPressed: cubit.loadPlugins,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (state.isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (state.plugins.isEmpty)
              Card(
                color: cs.surfaceContainerLow,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.extension_off_rounded,
                        size: 40,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No hay complementos instalados',
                        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Puedes instalar complementos externos en formato .zip con el botón superior.',
                        textAlign: TextAlign.center,
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              )
            else
              Card(
                color: cs.surfaceContainerLow,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: state.plugins.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final plugin = state.plugins[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: cs.primaryContainer,
                        foregroundColor: cs.onPrimaryContainer,
                        child: Icon(plugin.iconData, size: 22),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              plugin.name,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'v${plugin.version}',
                              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        plugin.description.isNotEmpty
                            ? plugin.description
                            : 'Por ${plugin.author}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: plugin.isEnabled,
                            onChanged: (val) => cubit.togglePlugin(plugin.id, val),
                          ),
                          if (plugin.directoryPath.isNotEmpty)
                            IconButton(
                              tooltip: 'Eliminar complemento',
                              icon: Icon(Icons.delete_outline_rounded, color: cs.error, size: 20),
                              onPressed: () => _confirmUninstall(context, plugin),
                            ),
                        ],
                      ),
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) => PluginDetailsDialog(plugin: plugin),
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}
