import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'common/epub/repositories/epub_repo.dart';
import 'common/widgets/speed_dial.dart';
import 'features/home/data/layout_repo.dart';
import 'features/search_replace/data/pill_order_repo.dart';
import 'features/search_replace/data/search_replace_repo.dart';
import 'features/search_replace/presentation/cubit/search_replace_cubit.dart';
import 'features/settings/data/preferences_repo.dart';
import 'features/settings/presentation/cubit/settings_cubit.dart';

final getIt = GetIt.instance;

Future<void> injectDependencies() async {
  // Externals
  final prefs = await SharedPreferences.getInstance();
  getIt.registerLazySingleton<SharedPreferences>(() => prefs);

  // Repositories
  getIt.registerLazySingleton<EpubRepository>(() => EpubRepositoryImpl());
  getIt.registerLazySingleton<SearchReplaceRepository>(() => SearchReplaceRepositoryImpl(getIt()));
  getIt.registerLazySingleton<PreferencesRepository>(() => PreferencesRepositoryImpl(getIt()));
  getIt.registerLazySingleton<LayoutRepository>(() => LayoutRepositoryImpl(getIt()));
  getIt.registerLazySingleton<PillOrderRepository>(() => PillOrderRepositoryImpl(getIt()));

  // Cubits
  getIt.registerFactory<SearchReplaceCubit>(() => SearchReplaceCubit(getIt(), getIt(), getIt()));
  getIt.registerFactory<SettingsCubit>(() => SettingsCubit(getIt()));

  getIt.registerLazySingleton<ValueNotifier<List<SpeedDialAction>>>(() => ValueNotifier<List<SpeedDialAction>>([]));
}
