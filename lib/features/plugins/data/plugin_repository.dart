import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/plugin_manifest.dart';
import 'plugin_registry.dart';

class PluginRepository {
  final SharedPreferences _prefs;
  Directory? _cachedPluginsDir;

  static final RegExp _validIdRegex = RegExp(r'^[a-zA-Z0-9_\-]+$');

  /// Valida que el identificador del complemento sea seguro y no contenga
  /// secuencias de escape de directorio o caracteres no permitidos.
  static bool isValidPluginId(String? id) {
    if (id == null || id.isEmpty || id.length > 64) return false;
    if (id == '.' || id == '..') return false;
    return _validIdRegex.hasMatch(id);
  }

  PluginRepository(this._prefs, {Directory? pluginsDirectory})
      : _cachedPluginsDir = pluginsDirectory;

  Future<Directory> getPluginsDirectory() async {
    if (_cachedPluginsDir != null) return _cachedPluginsDir!;

    try {
      // 1. Modo portable: revisar si existe carpeta 'plugins' junto al ejecutable
      final exeDir = File(Platform.resolvedExecutable).parent;
      final portablePlugins = Directory(p.join(exeDir.path, 'plugins'));
      if (await portablePlugins.exists()) {
        _cachedPluginsDir = portablePlugins;
        return portablePlugins;
      }
    } catch (_) {}

    // 2. Ruta estándar de soporte de la aplicación
    final appSupport = await getApplicationSupportDirectory();
    final pluginsDir = Directory(p.join(appSupport.path, 'plugins'));
    if (!await pluginsDir.exists()) {
      await pluginsDir.create(recursive: true);
    }
    _cachedPluginsDir = pluginsDir;
    return pluginsDir;
  }

  Future<List<PluginManifest>> loadPlugins({PluginRegistry? registry}) async {
    final List<PluginManifest> list = [];

    // 1. Cargar complementos registrados en código (nativos/paquetes)
    if (registry != null) {
      for (final ext in registry.allExtensions) {
        final isEnabled = _prefs.getBool('plugin_${ext.id}_enabled') ?? true;
        list.add(ext.manifest.copyWith(isEnabled: isEnabled));
      }
    }

    // 2. Cargar complementos desde disco (carpetas o instalados vía ZIP)
    final dir = await getPluginsDirectory();
    if (await dir.exists()) {
      final entities = dir.listSync();
      for (final entity in entities) {
        if (entity is Directory) {
          final manifestFile = File(p.join(entity.path, 'manifest.json'));
          if (await manifestFile.exists()) {
            try {
              final jsonStr = await manifestFile.readAsString();
              final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;
              final id = jsonMap['id'] as String? ?? p.basename(entity.path);
              // Validar que el identificador sea seguro
              if (!isValidPluginId(id)) continue;
              // Evitar duplicados si ya fue cargado desde el registro nativo
              if (list.any((p) => p.id == id)) continue;
              final isEnabled = _prefs.getBool('plugin_${id}_enabled') ?? true;
              list.add(PluginManifest.fromJson(jsonMap, entity.path, isEnabled: isEnabled));
            } catch (_) {}
          }
        }
      }
    }

    return list;
  }

  Future<PluginManifest> installPluginFromZip(String zipPath) async {
    final zipFile = File(zipPath);
    if (!await zipFile.exists()) {
      throw Exception('El archivo ZIP no existe: $zipPath');
    }

    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // Buscar manifest.json en el archivo
    ArchiveFile? manifestArchiveFile;
    String prefixToRemove = '';

    for (final file in archive) {
      if (file.name.endsWith('manifest.json')) {
        manifestArchiveFile = file;
        final parts = p.split(file.name);
        if (parts.length > 1) {
          prefixToRemove = '${parts.sublist(0, parts.length - 1).join('/')}/';
        }
        break;
      }
    }

    if (manifestArchiveFile == null) {
      throw const FormatException('El archivo ZIP no contiene un manifest.json válido');
    }

    final manifestContent = utf8.decode(manifestArchiveFile.content as List<int>);
    final manifestMap = jsonDecode(manifestContent) as Map<String, dynamic>;
    final rawId = manifestMap['id'] as String?;
    final pluginId = rawId ?? 'plugin_${DateTime.now().millisecondsSinceEpoch}';

    // 1. Validar que el id no contenga caracteres maliciosos o secuencias de escape de ruta
    if (!isValidPluginId(pluginId)) {
      throw FormatException(
        'El identificador del complemento "$pluginId" no es válido. '
        'Solo se permiten caracteres alfanuméricos, guiones y guiones bajos.',
      );
    }

    final pluginsDir = await getPluginsDirectory();
    final canonicalPluginsDir = p.canonicalize(pluginsDir.path);
    final targetDir = Directory(p.join(canonicalPluginsDir, pluginId));
    final canonicalTargetDir = p.canonicalize(targetDir.path);

    // 2. Asegurar que targetDir esté estrictamente contenido dentro de pluginsDir
    if (!p.isWithin(canonicalPluginsDir, canonicalTargetDir) ||
        p.equals(canonicalPluginsDir, canonicalTargetDir)) {
      throw const FormatException('Ruta de destino no válida para el complemento.');
    }

    if (await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
    await targetDir.create(recursive: true);

    // 3. Extraer archivos con protección estricta contra Zip Slip
    for (final file in archive) {
      if (file.isFile) {
        var relPath = file.name;
        if (prefixToRemove.isNotEmpty && relPath.startsWith(prefixToRemove)) {
          relPath = relPath.substring(prefixToRemove.length);
        }
        if (relPath.isEmpty) continue;

        // Normalizar ruta para detectar intentos de escape (Zip Slip)
        final normalized = p.normalize(relPath);
        if (p.isAbsolute(normalized) ||
            normalized.startsWith('..') ||
            normalized.contains('/../') ||
            normalized.contains(r'\..\')) {
          throw FormatException('Ruta insegura en archivo ZIP (escape de directorio): ${file.name}');
        }

        final destinationPath = p.canonicalize(p.join(canonicalTargetDir, normalized));
        if (!p.isWithin(canonicalTargetDir, destinationPath)) {
          throw FormatException('Intento de Zip Slip detectado en archivo: ${file.name}');
        }

        final outFile = File(destinationPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      }
    }

    await _prefs.setBool('plugin_${pluginId}_enabled', true);
    return PluginManifest.fromJson(manifestMap, targetDir.path, isEnabled: true);
  }

  Future<void> setPluginEnabled(String id, bool enabled) async {
    await _prefs.setBool('plugin_${id}_enabled', enabled);
  }

  Future<void> uninstallPlugin(String id, String directoryPath) async {
    final pluginsDir = await getPluginsDirectory();
    final canonicalPluginsDir = p.canonicalize(pluginsDir.path);

    // Solo permitir borrar directorios que estén estrictamente dentro de pluginsDir
    if (directoryPath.isNotEmpty) {
      final canonicalDirPath = p.canonicalize(directoryPath);
      if (p.isWithin(canonicalPluginsDir, canonicalDirPath)) {
        final dir = Directory(canonicalDirPath);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    }
    await _prefs.remove('plugin_${id}_enabled');
  }

  Future<void> openPluginsDirectory() async {
    final dir = await getPluginsDirectory();
    if (Platform.isWindows) {
      await Process.run('explorer.exe', [dir.path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [dir.path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [dir.path]);
    }
  }
}
