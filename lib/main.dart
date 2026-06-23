import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'inject_dependencies.dart';
import 'common/router/app_router.dart';
import 'common/theme/app_theme.dart';
import 'common/window/window_setup.dart';
import 'features/settings/presentation/cubit/settings_cubit.dart';
import 'features/settings/presentation/cubit/settings_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await injectDependencies();

  final windowSetup = WindowSetup(prefs: getIt());
  await windowSetup.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<SettingsCubit>(),
      child: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          return MaterialApp.router(
            title: 'ZeeTools',
            debugShowCheckedModeBanner: false,
            themeMode: state.preferences.themeMode,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            routerConfig: appRouter,
          );
        },
      ),
    );
  }
}
