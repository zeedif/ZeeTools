import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/home/presentation/models/speed_dial_action.dart';
import 'features/home/repositories/layout_repo.dart';
import 'features/settings/data/repositories/preferences_repo.dart';
import 'features/settings/presentation/cubit/settings_cubit.dart';

final getIt = GetIt.instance;

Future<void> injectDependencies() async {
  // Externals
  final prefs = await SharedPreferences.getInstance();
  getIt.registerLazySingleton<SharedPreferences>(() => prefs);

  // Repositories
  getIt.registerLazySingleton<PreferencesRepository>(() => PreferencesRepositoryImpl(getIt()));
  getIt.registerLazySingleton<LayoutRepository>(() => LayoutRepositoryImpl(getIt()));

  // Cubits
  getIt.registerFactory<SettingsCubit>(() => SettingsCubit(getIt()));

  getIt.registerLazySingleton<ValueNotifier<List<SpeedDialAction>>>(() => ValueNotifier<List<SpeedDialAction>>([]));
}
