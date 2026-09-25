import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'common/router/app_router.dart';
import 'common/theme/app_theme.dart';
import 'features/settings/presentation/cubit/settings_cubit.dart';
import 'features/settings/presentation/cubit/settings_state.dart';
import 'inject_dependencies.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WindowListener {
  Timer? _sizeDebounce;
  Timer? _posDebounce;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _sizeDebounce?.cancel();
    _posDebounce?.cancel();
    super.dispose();
  }

  @override
  void onWindowResize() {
    _sizeDebounce?.cancel();
    _sizeDebounce = Timer(const Duration(milliseconds: 250), _saveSize);
  }

  @override
  void onWindowMove() {
    _posDebounce?.cancel();
    _posDebounce = Timer(const Duration(milliseconds: 250), _savePosition);
  }

  Future<void> _saveSize() async {
    final size = await windowManager.getSize();
    final prefs = getIt<SharedPreferences>();
    await prefs.setDouble('window_width', size.width);
    await prefs.setDouble('window_height', size.height);
  }

  Future<void> _savePosition() async {
    final pos = await windowManager.getPosition();
    final prefs = getIt<SharedPreferences>();
    await prefs.setDouble('window_x', pos.dx);
    await prefs.setDouble('window_y', pos.dy);
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<SettingsCubit>(),
      child: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (_, state) => MaterialApp.router(
          title: 'ZeeTools',
          debugShowCheckedModeBanner: false,
          themeMode: state.preferences.themeMode,
          theme: buildAppTheme(
            ColorScheme.fromSeed(seedColor: appSeedColor, brightness: Brightness.light),
          ),
          darkTheme: buildAppTheme(
            ColorScheme.fromSeed(seedColor: appSeedColor, brightness: Brightness.dark),
          ),
          routerConfig: appRouter,
        ),
      ),
    );
  }
}
