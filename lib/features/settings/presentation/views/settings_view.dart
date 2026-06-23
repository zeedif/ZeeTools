import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          return ListView(
            padding: const EdgeInsets.all(12.0),
            children: [
              ListTile(
                title: const Text('Tema de la aplicación'),
                subtitle: const Text(
                  'Elige el tema de la aplicación o usa \'Sistema\' para alinearlo con tu dispositivo.',
                ),
                trailing: DropdownMenu<ThemeMode>(
                  key: ValueKey(state.preferences.themeMode),
                  initialSelection: state.preferences.themeMode,
                  requestFocusOnTap: false,
                  enableFilter: false,
                  enableSearch: false,
                  textStyle: const TextStyle(fontSize: 14),
                  menuStyle: MenuStyle(
                    padding: WidgetStateProperty.all(EdgeInsets.zero),
                  ),
                  inputDecorationTheme: InputDecorationTheme(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSelected: (mode) {
                    if (mode != null) {
                      context.read<SettingsCubit>().changeTheme(mode);
                    }
                  },
                  dropdownMenuEntries: const [
                    DropdownMenuEntry(value: ThemeMode.system, label: 'Sistema'),
                    DropdownMenuEntry(value: ThemeMode.light, label: 'Claro'),
                    DropdownMenuEntry(value: ThemeMode.dark, label: 'Oscuro'),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
