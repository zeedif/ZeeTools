import 'package:flutter/material.dart';

import '../../domain/plugin_manifest.dart';

class PluginDetailsDialog extends StatelessWidget {
  final PluginManifest plugin;

  const PluginDetailsDialog({super.key, required this.plugin});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(plugin.iconData, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(plugin.name)),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [
                Chip(
                  label: Text('Versión ${plugin.version}'),
                  visualDensity: VisualDensity.compact,
                ),
                Chip(
                  label: Text('Por ${plugin.author}'),
                  visualDensity: VisualDensity.compact,
                ),
                Chip(
                  avatar: Icon(
                    plugin.isEnabled ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
                    size: 16,
                    color: plugin.isEnabled ? Colors.green : Colors.grey,
                  ),
                  label: Text(plugin.isEnabled ? 'Habilitado' : 'Deshabilitado'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (plugin.description.isNotEmpty) ...[
              Text('Descripción:', style: tt.labelLarge),
              const SizedBox(height: 4),
              Text(plugin.description, style: tt.bodyMedium),
              const SizedBox(height: 16),
            ],
            Text('Identificador:', style: tt.labelLarge),
            SelectableText(plugin.id, style: tt.bodySmall),
            const SizedBox(height: 12),
            Text('Ubicación:', style: tt.labelLarge),
            SelectableText(plugin.directoryPath, style: tt.bodySmall),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
