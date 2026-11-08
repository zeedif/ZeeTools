import 'package:flutter/material.dart';

import 'plugin_manifest.dart';

/// Contract for a native Dart extension that integrates with ZeeTools.
///
/// Implement this interface to register a plugin that can render a full
/// Flutter [Widget] inside ZeeTools, using the host app's theme and routing.
///
/// ## Registering an extension
///
/// ```dart
/// // In your plugin adapter file:
/// class MyExtension implements ZeeToolsPluginExtension {
///   const MyExtension();
///
///   @override
///   String get id => 'my_tool'; // Must match manifest.json "id"
///
///   @override
///   Widget buildView(BuildContext context, PluginManifest manifest) {
///     return const MyToolView();
///   }
/// }
///
/// // In inject_dependencies.dart:
/// pluginRegistry.register(const MyExtension());
/// ```
///
/// The [id] must exactly match the `"id"` field in the plugin's `manifest.json`.
/// ZeeTools uses this key to resolve the correct [ZeeToolsPluginExtension] at
/// runtime when navigating to `/plugin/:id`.
abstract class ZeeToolsPluginExtension {
  /// The unique identifier that binds this extension to a [PluginManifest].
  ///
  /// Must match the `"id"` field in the plugin's `manifest.json` exactly.
  String get id;

  /// The declarative metadata and manifest for this plugin extension.
  ///
  /// Can be overridden to declare the plugin's name, version, icon, and
  /// description directly in code for built-in or package-based plugins.
  PluginManifest get manifest => PluginManifest(
        id: id,
        name: id,
        version: '1.0.0',
        author: 'ZeeTools Extension',
        description: '',
        directoryPath: '',
      );

  /// Builds the root view for this plugin.
  ///
  /// Called when the user navigates to the plugin's route (`/plugin/:id`).
  /// The [manifest] contains all metadata for this plugin instance, including
  /// the user-configured [PluginManifest.isEnabled] state.
  Widget buildView(BuildContext context, PluginManifest manifest);
}
