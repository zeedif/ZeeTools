import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'common/epub/repositories/epub_repo.dart';
import 'common/process/native_tools_repo.dart';
import 'common/widgets/speed_dial.dart';
import 'features/epub_migrator/data/epub_migrator_repo.dart';
import 'features/epub_migrator/presentation/cubit/epub_migrator_cubit.dart';
import 'features/epub_templater/data/amazon_repo.dart';
import 'features/epub_templater/data/epub_templater_repo.dart';
import 'features/epub_templater/data/template_profiles_repo.dart';
import 'features/epub_templater/presentation/cubit/epub_templater_cubit.dart';
import 'features/home/data/layout_repo.dart';
import 'features/image_optimizer/data/image_optimizer_engine.dart';
import 'features/image_optimizer/data/image_optimizer_repo.dart';
import 'features/image_optimizer/data/image_optimizer_settings_repo.dart';
import 'features/image_optimizer/presentation/cubit/image_optimizer_cubit.dart';
import 'features/metadata_editor/data/epub_metadata_repo.dart';
import 'features/metadata_editor/presentation/cubit/metadata_editor_cubit.dart';
import 'features/search_replace/data/search_replace_repo.dart';
import 'features/search_replace/data/search_replace_settings_repo.dart';
import 'features/search_replace/presentation/cubit/search_replace_cubit.dart';
import 'features/settings/data/preferences_repo.dart';
import 'features/settings/presentation/cubit/settings_cubit.dart';
import 'features/plugins/data/plugin_registry.dart';
import 'features/plugins/data/plugin_repository.dart';
import 'features/plugins/presentation/cubit/plugins_cubit.dart';
import 'plugins_init.dart';

final getIt = GetIt.instance;

Future<void> injectDependencies() async {
  // Externals
  final prefs = await SharedPreferences.getInstance();
  getIt.registerLazySingleton<SharedPreferences>(() => prefs);
  final supportDir = await getApplicationSupportDirectory();

  // Plugins System (Picard-style extensible architecture)
  final pluginRegistry = PluginRegistry();
  registerCustomPlugins(pluginRegistry);
  getIt.registerLazySingleton<PluginRegistry>(() => pluginRegistry);
  getIt.registerLazySingleton<PluginRepository>(() => PluginRepository(getIt()));
  getIt.registerLazySingleton<PluginsCubit>(() => PluginsCubit(getIt(), getIt<PluginRegistry>()));

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
  getIt.registerLazySingleton<EpubTemplaterRepository>(() => EpubTemplaterRepositoryImpl());
  getIt.registerLazySingleton<TemplateProfilesRepository>(() => TemplateProfilesRepositoryImpl(getIt(), p.join(supportDir.path, 'perfiles')));
  getIt.registerLazySingleton<AmazonRepository>(() => AmazonRepositoryImpl(p.join(supportDir.path, 'amazon')));
  getIt.registerLazySingleton<EpubMigratorRepository>(() => EpubMigratorRepositoryImpl());
  getIt.registerLazySingleton<EpubMetadataRepository>(() => EpubMetadataRepositoryImpl(EpubRepositoryImpl()));

  // Cubits
  getIt.registerFactory<SearchReplaceCubit>(() => SearchReplaceCubit(getIt(), getIt(), getIt()));
  getIt.registerFactory<SettingsCubit>(() => SettingsCubit(getIt()));
  getIt.registerFactory<ImageOptimizerCubit>(() => ImageOptimizerCubit(getIt(), getIt()));
  getIt.registerFactory<EpubTemplaterCubit>(() => EpubTemplaterCubit(getIt(), getIt(), getIt(), getIt()));
  getIt.registerFactory<MetadataEditorCubit>(() => MetadataEditorCubit(getIt()));
  getIt.registerFactory<EpubMigratorCubit>(() => EpubMigratorCubit(getIt()));

  getIt.registerLazySingleton<ValueNotifier<List<SpeedDialAction>>>(() => ValueNotifier<List<SpeedDialAction>>([]));
}
