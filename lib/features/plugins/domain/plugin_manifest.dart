import 'package:flutter/material.dart';

/// Represents all metadata associated with an installed ZeeTools plugin.
///
/// Parsed from a `manifest.json` file located in the plugin's directory.
/// This object is the single source of truth for plugin identity, display
/// information, and runtime behavior flags.
class PluginManifest {
  /// The unique identifier for this plugin, used for routing and storage keys.
  final String id;

  /// The human-readable name displayed in the dashboard and settings.
  final String name;

  /// The semver-compatible version string (e.g. `"1.2.0"`).
  final String version;

  /// The name of the author or team that published this plugin.
  final String author;

  /// A short description of the plugin's purpose, shown in the details dialog.
  final String description;

  /// The icon key used to resolve an [IconData] via [iconData].
  ///
  /// Accepted values: `auto_stories`, `book`, `menu_book`, `translate`, etc.
  /// Falls back to [Icons.extension_rounded] for any unrecognized value.
  final String icon;

  /// Whether the plugin is currently active and shown on the dashboard.
  final bool isEnabled;

  /// The absolute path to the directory where this plugin is installed.
  final String directoryPath;

  /// The relative path to the plugin's Dart entry point, if declared.
  ///
  /// Used by native Dart extension plugins. Optional for manifest-only plugins.
  final String? entryPoint;

  /// Any additional fields parsed from `manifest.json` not covered by the
  /// standard schema.
  final Map<String, dynamic> extra;

  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.author,
    required this.description,
    this.icon = 'extension',
    this.isEnabled = true,
    this.directoryPath = '',
    this.entryPoint,
    this.extra = const {},
  });

  /// Constructs a [PluginManifest] from a parsed `manifest.json` map.
  ///
  /// [directoryPath] is the absolute path to the installed plugin folder.
  /// [isEnabled] reflects the persisted user toggle state (default: `true`).
  ///
  /// All fields fall back to safe defaults when missing from [json].
  factory PluginManifest.fromJson(
    Map<String, dynamic> json,
    String directoryPath, {
    bool isEnabled = true,
  }) {
    return PluginManifest(
      id: json['id'] as String? ?? 'plugin_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Complemento sin nombre',
      version: json['version'] as String? ?? '1.0.0',
      author: json['author'] as String? ?? 'Desconocido',
      description: json['description'] as String? ?? '',
      icon: json['icon'] as String? ?? 'extension',
      isEnabled: isEnabled,
      directoryPath: directoryPath,
      entryPoint: json['entry_point'] as String?,
      extra: json,
    );
  }

  /// Returns a copy with [isEnabled] overridden.
  PluginManifest copyWith({bool? isEnabled}) {
    return PluginManifest(
      id: id,
      name: name,
      version: version,
      author: author,
      description: description,
      icon: icon,
      isEnabled: isEnabled ?? this.isEnabled,
      directoryPath: directoryPath,
      entryPoint: entryPoint,
      extra: extra,
    );
  }

  /// The Material icon corresponding to the [icon] key declared in the manifest.
  IconData get iconData {
    return switch (icon.toLowerCase().trim()) {
      'auto_stories' => Icons.auto_stories_rounded,
      'menu_book' => Icons.menu_book_rounded,
      'book' => Icons.book_rounded,
      'library_books' => Icons.library_books_rounded,
      'translate' => Icons.translate_rounded,
      'find_replace' => Icons.find_replace_rounded,
      'palette' => Icons.palette_rounded,
      'image' => Icons.image_rounded,
      'tag' => Icons.tag_rounded,
      'terminal' => Icons.terminal_rounded,
      'code' => Icons.code_rounded,
      'cloud_download' => Icons.cloud_download_rounded,
      'cloud_upload' => Icons.cloud_upload_rounded,
      'send' => Icons.send_rounded,
      'settings' => Icons.settings_rounded,
      'build' => Icons.build_rounded,
      'calendar' || 'calendar_month' || 'calendar_today' || 'schedule' => Icons.calendar_month_rounded,
      'groups' || 'group' || 'people' => Icons.groups_rounded,
      _ => Icons.extension_rounded,
    };
  }
}
