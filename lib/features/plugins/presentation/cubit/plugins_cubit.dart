import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/plugin_registry.dart';
import '../../data/plugin_repository.dart';
import 'plugins_state.dart';

class PluginsCubit extends Cubit<PluginsState> {
  final PluginRepository _repository;
  final PluginRegistry? _registry;

  PluginsCubit(this._repository, [this._registry]) : super(const PluginsState()) {
    loadPlugins();
  }

  Future<void> loadPlugins() async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    try {
      final list = await _repository.loadPlugins(registry: _registry);
      emit(state.copyWith(plugins: list, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: 'Error al cargar complementos: $e'));
    }
  }

  Future<void> togglePlugin(String id, bool enabled) async {
    await _repository.setPluginEnabled(id, enabled);
    final updated = state.plugins.map((p) => p.id == id ? p.copyWith(isEnabled: enabled) : p).toList();
    emit(state.copyWith(plugins: updated));
  }

  Future<void> installFromZip(String zipPath) async {
    emit(state.copyWith(isLoading: true, errorMessage: null, successMessage: null));
    try {
      final installed = await _repository.installPluginFromZip(zipPath);
      final list = await _repository.loadPlugins(registry: _registry);
      emit(state.copyWith(
        plugins: list,
        isLoading: false,
        successMessage: 'Complemento "${installed.name}" instalado con éxito.',
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: 'Error al instalar el complemento: $e'));
    }
  }

  Future<void> uninstallPlugin(String id, String directoryPath) async {
    try {
      await _repository.uninstallPlugin(id, directoryPath);
      final list = await _repository.loadPlugins(registry: _registry);
      emit(state.copyWith(plugins: list, successMessage: 'Complemento desinstalado.'));
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Error al desinstalar: $e'));
    }
  }

  Future<void> openFolder() async {
    await _repository.openPluginsDirectory();
  }
}
