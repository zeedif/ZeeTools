import '../../domain/plugin_manifest.dart';

class PluginsState {
  final List<PluginManifest> plugins;
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;

  const PluginsState({
    this.plugins = const [],
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
  });

  List<PluginManifest> get enabledPlugins => plugins.where((p) => p.isEnabled).toList();

  PluginsState copyWith({
    List<PluginManifest>? plugins,
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
  }) {
    return PluginsState(
      plugins: plugins ?? this.plugins,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      successMessage: successMessage,
    );
  }
}
