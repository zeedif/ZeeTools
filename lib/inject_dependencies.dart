import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'common/epub/repositories/epub_repo.dart';
import 'common/process/native_tools_repo.dart';
import 'common/widgets/speed_dial.dart';
import 'features/home/data/layout_repo.dart';
import 'features/image_optimizer/data/image_optimizer_engine.dart';
import 'features/image_optimizer/data/image_optimizer_repo.dart';
import 'features/image_optimizer/data/image_optimizer_settings_repo.dart';
import 'features/image_optimizer/presentation/cubit/image_optimizer_cubit.dart';
import 'features/search_replace/data/search_replace_repo.dart';
import 'features/search_replace/data/search_replace_settings_repo.dart';
import 'features/search_replace/presentation/cubit/search_replace_cubit.dart';
import 'features/settings/data/preferences_repo.dart';
import 'features/settings/presentation/cubit/settings_cubit.dart';

final getIt = GetIt.instance;

Future<void> injectDependencies() async {
  // Externals
  final prefs = await SharedPreferences.getInstance();
  getIt.registerLazySingleton<SharedPreferences>(() => prefs);
  final supportDir = await getApplicationSupportDirectory();

  // Repositories
  getIt.registerLazySingleton<EpubRepository>(() => EpubRepositoryImpl());
  getIt.registerLazySingleton<SearchReplaceRepository>(() => SearchReplaceRepositoryImpl(getIt()));
  getIt.registerLazySingleton<PreferencesRepository>(() => PreferencesRepositoryImpl(getIt()));
  getIt.registerLazySingleton<LayoutRepository>(() => LayoutRepositoryImpl(getIt()));
  getIt.registerLazySingleton<SearchReplaceSettingsRepository>(() => SearchReplaceSettingsRepositoryImpl(getIt()));
  getIt.registerLazySingleton<NativeToolsRepository>(() => NativeToolsRepositoryImpl(p.join(supportDir.path, 'tools')));
  getIt.registerLazySingleton<ImageOptimizerSettingsRepository>(() => ImageOptimizerSettingsRepositoryImpl(getIt()));
  // Caché de EPUBs independiente de la de búsqueda y reemplazo.
  getIt.registerLazySingleton<ImageOptimizerRepository>(() => ImageOptimizerRepositoryImpl(EpubRepositoryImpl(), getIt(), ImageOptimizerEngine()));

  // Cubits
  getIt.registerFactory<SearchReplaceCubit>(() => SearchReplaceCubit(getIt(), getIt(), getIt()));
  getIt.registerFactory<SettingsCubit>(() => SettingsCubit(getIt()));
  getIt.registerFactory<ImageOptimizerCubit>(() => ImageOptimizerCubit(getIt(), getIt()));

  getIt.registerLazySingleton<ValueNotifier<List<SpeedDialAction>>>(() => ValueNotifier<List<SpeedDialAction>>([]));
}
