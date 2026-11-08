import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeetools/features/plugins/data/plugin_registry.dart';
import 'package:zeetools/features/plugins/data/plugin_repository.dart';
import 'package:zeetools/features/plugins/domain/plugin_manifest.dart';
import 'package:zeetools/features/plugins/presentation/cubit/plugins_cubit.dart';
import 'package:zeetools/features/plugins/presentation/cubit/plugins_state.dart';

class FakePluginRepository implements PluginRepository {
  List<PluginManifest> pluginsToReturn = [];
  bool throwOnLoad = false;
  bool throwOnInstall = false;
  bool throwOnUninstall = false;
  String? lastToggledId;
  bool? lastToggledEnabled;
  PluginManifest? pluginToInstall;
  String? lastUninstalledId;
  String? lastUninstalledPath;
  bool openFolderCalled = false;

  @override
  Future<List<PluginManifest>> loadPlugins({PluginRegistry? registry}) async {
    if (throwOnLoad) throw Exception('disco lleno');
    return pluginsToReturn;
  }

  @override
  Future<void> setPluginEnabled(String id, bool enabled) async {
    lastToggledId = id;
    lastToggledEnabled = enabled;
  }

  @override
  Future<PluginManifest> installPluginFromZip(String zipPath) async {
    if (throwOnInstall) throw Exception('zip corrupto');
    return pluginToInstall ?? PluginManifest(
      id: 'nuevo',
      name: 'Plugin nuevo',
      version: '1.0.0',
      author: 'Test',
      description: 'Test description',
      directoryPath: '/tmp/plugins/nuevo',
      isEnabled: true,
    );
  }

  @override
  Future<void> uninstallPlugin(String id, String directoryPath) async {
    if (throwOnUninstall) throw Exception('permiso denegado');
    lastUninstalledId = id;
    lastUninstalledPath = directoryPath;
  }

  @override
  Future<void> openPluginsDirectory() async {
    openFolderCalled = true;
  }

  @override
  Future<Directory> getPluginsDirectory() async => Directory('/tmp');
}

void main() {
  late FakePluginRepository fakeRepo;
  late PluginsCubit cubit;

  PluginManifest createManifest(String id, {bool enabled = true}) => PluginManifest(
        id: id,
        name: 'Plugin $id',
        version: '1.0.0',
        author: 'Test',
        description: '',
        directoryPath: '/tmp/plugins/$id',
        isEnabled: enabled,
      );

  setUp(() {
    fakeRepo = FakePluginRepository();
    cubit = PluginsCubit(fakeRepo);
  });

  tearDown(() => cubit.close());

  group('PluginsCubit.loadPlugins', () {
    test('emite estado cargado con la lista del repositorio', () async {
      final plugins = [createManifest('a'), createManifest('b')];
      fakeRepo.pluginsToReturn = plugins;

      await cubit.loadPlugins();

      expect(cubit.state.plugins, equals(plugins));
      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.errorMessage, isNull);
    });

    test('emite errorMessage cuando el repositorio lanza excepción', () async {
      fakeRepo.throwOnLoad = true;

      await cubit.loadPlugins();

      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.errorMessage, contains('disco lleno'));
      expect(cubit.state.plugins, isEmpty);
    });
  });

  group('PluginsCubit.togglePlugin', () {
    test('actualiza isEnabled del plugin correcto sin afectar otros', () async {
      final plugins = [createManifest('a'), createManifest('b')];
      fakeRepo.pluginsToReturn = plugins;

      await cubit.loadPlugins();
      await cubit.togglePlugin('a', false);

      final result = cubit.state.plugins;
      expect(result.firstWhere((p) => p.id == 'a').isEnabled, isFalse);
      expect(result.firstWhere((p) => p.id == 'b').isEnabled, isTrue);
      expect(fakeRepo.lastToggledId, 'a');
      expect(fakeRepo.lastToggledEnabled, isFalse);
    });

    test('llama a setPluginEnabled en el repositorio con los valores correctos', () async {
      fakeRepo.pluginsToReturn = [createManifest('a')];

      await cubit.loadPlugins();
      await cubit.togglePlugin('a', false);

      expect(fakeRepo.lastToggledId, 'a');
      expect(fakeRepo.lastToggledEnabled, isFalse);
    });
  });

  group('PluginsCubit.installFromZip', () {
    test('emite successMessage con el nombre del plugin instalado', () async {
      final installed = createManifest('nuevo');
      fakeRepo.pluginToInstall = installed;
      fakeRepo.pluginsToReturn = [installed];

      await cubit.installFromZip('/tmp/nuevo_plugin.zip');

      expect(cubit.state.successMessage, contains('Plugin nuevo'));
      expect(cubit.state.isLoading, isFalse);
    });

    test('emite errorMessage cuando el zip es inválido', () async {
      fakeRepo.throwOnInstall = true;

      await cubit.installFromZip('/tmp/corrupto.zip');

      expect(cubit.state.errorMessage, contains('zip corrupto'));
      expect(cubit.state.isLoading, isFalse);
    });
  });

  group('PluginsCubit.uninstallPlugin', () {
    test('recarga la lista tras desinstalar y emite successMessage', () async {
      fakeRepo.pluginsToReturn = [];

      await cubit.uninstallPlugin('a', '/tmp/plugins/a');

      expect(cubit.state.successMessage, isNotNull);
      expect(fakeRepo.lastUninstalledId, 'a');
      expect(fakeRepo.lastUninstalledPath, '/tmp/plugins/a');
    });

    test('emite errorMessage cuando la desinstalación falla', () async {
      fakeRepo.throwOnUninstall = true;

      await cubit.uninstallPlugin('a', '/tmp/plugins/a');

      expect(cubit.state.errorMessage, contains('permiso denegado'));
    });
  });

  group('PluginsState.enabledPlugins', () {
    test('filtra correctamente sólo los plugins activos', () {
      final state = PluginsState(
        plugins: [
          createManifest('a'),
          createManifest('b', enabled: false),
          createManifest('c'),
        ],
      );

      final enabled = state.enabledPlugins;
      expect(enabled.map((p) => p.id), containsAll(['a', 'c']));
      expect(enabled.any((p) => p.id == 'b'), isFalse);
    });
  });
}
