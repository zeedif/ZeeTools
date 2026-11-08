import '../domain/plugin_extension.dart';

/// In-memory registry of active [ZeeToolsPluginExtension] instances.
///
/// Acts as the runtime bridge between installed plugins (identified by
/// [PluginManifest.id]) and their native Dart widget implementations.
///
/// Extensions are registered at app startup via [register] and can be
/// removed at runtime via [unregister]. Only extensions that are both
/// registered here *and* have their corresponding [PluginManifest.isEnabled]
/// set to `true` will be rendered on the dashboard and routable via
/// `/plugin/:id`.
///
/// ## Typical usage
///
/// ```dart
/// // In inject_dependencies.dart — startup:
/// final registry = PluginRegistry();
/// registry.register(const MyExtension());
/// getIt.registerLazySingleton<PluginRegistry>(() => registry);
/// ```
class PluginRegistry {
  final Map<String, ZeeToolsPluginExtension> _extensions = {};

  /// Registers [extension] under its [ZeeToolsPluginExtension.id].
  ///
  /// Replaces any previously registered extension with the same id.
  void register(ZeeToolsPluginExtension extension) {
    _extensions[extension.id] = extension;
  }

  /// Removes the extension registered under [id], if any.
  void unregister(String id) {
    _extensions.remove(id);
  }

  /// Returns the extension registered under [id], or `null` if absent.
  ZeeToolsPluginExtension? get(String id) => _extensions[id];

  /// Whether an extension is registered under [id].
  bool has(String id) => _extensions.containsKey(id);

  /// Returns a list of all currently registered [ZeeToolsPluginExtension] instances.
  List<ZeeToolsPluginExtension> get allExtensions => _extensions.values.toList();
}
