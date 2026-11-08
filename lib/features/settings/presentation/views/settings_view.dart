import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '/common/theme/app_dimensions.dart';
import '/common/widgets/form_section.dart';
import '/common/widgets/outlined_dropdown.dart';
import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';
import '/features/plugins/presentation/views/plugins_settings_section.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          return ListView(
            padding: const EdgeInsets.all(AppPadding.large),
            children: [
              FormSection(
                title: 'Apariencia',
                children: [
                  OutlinedDropdown<ThemeMode>(
                    label: 'Tema de la aplicación',
                    helper: 'Sistema sigue el tema de tu dispositivo.',
                    value: state.preferences.themeMode,
                    onChanged: (mode) {
                      if (mode != null) context.read<SettingsCubit>().changeTheme(mode);
                    },
                    items: const [
                      DropdownMenuItem(value: ThemeMode.system, child: Text('Sistema')),
                      DropdownMenuItem(value: ThemeMode.light, child: Text('Claro')),
                      DropdownMenuItem(value: ThemeMode.dark, child: Text('Oscuro')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.large),
              const PluginsSettingsSection(),
            ],
          );
        },
      ),
    );
  }
}
