import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zeetools/features/plugins/data/plugin_registry.dart';
import 'package:zeetools/features/plugins/data/plugin_repository.dart';
import 'package:zeetools/features/plugins/domain/plugin_extension.dart';
import 'package:zeetools/features/plugins/domain/plugin_manifest.dart';

class _MockExtension implements ZeeToolsPluginExtension {
  final String _id;
  const _MockExtension([this._id = 'test_plugin']);

  @override
  String get id => _id;

  @override
  PluginManifest get manifest => PluginManifest(
        id: _id,
        name: 'Mock $_id',
        version: '1.0.0',
        author: 'Test',
        description: 'Test mock extension',
      );

  @override
  Widget buildView(BuildContext context, PluginManifest manifest) => Text('Plugin View $_id');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PluginManifest', () {
    test('parses valid manifest correctly', () {
      const rawJson = '''{
        "id": "sample_tool",
        "name": "Herramienta de Prueba",
        "version": "1.0.0",
        "description": "Una herramienta para pruebas",
        "author": "Comunidad",
        "icon": "book",
        "entry_point": "lib/main.dart"
      }''';

      final map = jsonDecode(rawJson) as Map<String, dynamic>;
      final manifest = PluginManifest.fromJson(
        map,
        '/plugins/sample_tool',
        isEnabled: true,
      );

      expect(manifest.id, 'sample_tool');
      expect(manifest.name, 'Herramienta de Prueba');
      expect(manifest.version, '1.0.0');
      expect(manifest.author, 'Comunidad');
      expect(manifest.iconData, Icons.book_rounded);
      expect(manifest.entryPoint, 'lib/main.dart');
      expect(manifest.isEnabled, isTrue);
    });

    test('falls back gracefully on empty or missing fields', () {
      final manifest = PluginManifest.fromJson(
        {},
        '/plugins/empty',
        isEnabled: false,
      );

      expect(manifest.name, 'Complemento sin nombre');
      expect(manifest.version, '1.0.0');
      expect(manifest.iconData, Icons.extension_rounded);
      expect(manifest.isEnabled, isFalse);
    });

    test('resolves calendar, groups and cloud_upload icons correctly', () {
      final mCalendar = PluginManifest.fromJson(const {'icon': 'calendar_month'}, '/p', isEnabled: true);
      final mGroups = PluginManifest.fromJson(const {'icon': 'groups'}, '/p', isEnabled: true);
      final mUpload = PluginManifest.fromJson(const {'icon': 'cloud_upload'}, '/p', isEnabled: true);

      expect(mCalendar.iconData, equals(Icons.calendar_month_rounded));
      expect(mGroups.iconData, equals(Icons.groups_rounded));
      expect(mUpload.iconData, equals(Icons.cloud_upload_rounded));
    });
  });

  group('PluginRegistry', () {
    test('registers and retrieves extensions', () {
      final registry = PluginRegistry();
      expect(registry.has('test_plugin'), isFalse);

      const ext = _MockExtension();
      registry.register(ext);

      expect(registry.has('test_plugin'), isTrue);
      expect(registry.get('test_plugin'), equals(ext));

      registry.unregister('test_plugin');
      expect(registry.has('test_plugin'), isFalse);
      expect(registry.get('test_plugin'), isNull);
    });

    test('registers and retrieves multiple modular extensions', () {
      final registry = PluginRegistry();
      const extA = _MockExtension('tool_a');
      const extB = _MockExtension('tool_b');
      const extC = _MockExtension('tool_c');

      registry.register(extA);
      registry.register(extB);
      registry.register(extC);

      expect(registry.get('tool_a'), equals(extA));
      expect(registry.get('tool_b'), equals(extB));
      expect(registry.get('tool_c'), equals(extC));
    });

    test('allExtensions returns all registered extensions', () {
      final registry = PluginRegistry();
      const extA = _MockExtension('tool_a');
      const extB = _MockExtension('tool_b');
      registry.register(extA);
      registry.register(extB);
      expect(registry.allExtensions, containsAll([extA, extB]));
    });
  });

  group('PluginRepository — Seguridad de Rutas y Prevención de Zip Slip', () {
    test('isValidPluginId validates identifiers strictly', () {
      // Identificadores válidos
      expect(PluginRepository.isValidPluginId('valid_plugin_123'), isTrue);
      expect(PluginRepository.isValidPluginId('my-tool-v2'), isTrue);
      expect(PluginRepository.isValidPluginId('extension_a'), isTrue);

      // Identificadores maliciosos o no permitidos
      expect(PluginRepository.isValidPluginId('../escape'), isFalse);
      expect(PluginRepository.isValidPluginId('../../root'), isFalse);
      expect(PluginRepository.isValidPluginId('/etc/passwd'), isFalse);
      expect(PluginRepository.isValidPluginId(r'C:\Windows'), isFalse);
      expect(PluginRepository.isValidPluginId('id con espacios'), isFalse);
      expect(PluginRepository.isValidPluginId('..'), isFalse);
      expect(PluginRepository.isValidPluginId('.'), isFalse);
      expect(PluginRepository.isValidPluginId(''), isFalse);
      expect(PluginRepository.isValidPluginId(null), isFalse);
    });

    test('installPluginFromZip rejects manifest with path traversal id', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final tempDir = await Directory.systemTemp.createTemp('zeetools_test_sec_');
      final pluginsDir = Directory(p.join(tempDir.path, 'plugins'));
      await pluginsDir.create();

      final repo = PluginRepository(prefs, pluginsDirectory: pluginsDir);

      // Crear archivo ZIP con manifest malicioso
      final archive = Archive();
      final manifestJson = utf8.encode('{"id": "../../malicious_escape", "name": "Evil"}');
      archive.addFile(ArchiveFile('manifest.json', manifestJson.length, manifestJson));
      final zipBytes = ZipEncoder().encode(archive);

      final zipFile = File(p.join(tempDir.path, 'test_malicious_id.zip'));
      await zipFile.writeAsBytes(zipBytes);

      await expectLater(
        () => repo.installPluginFromZip(zipFile.path),
        throwsA(isA<FormatException>()),
      );

      await tempDir.delete(recursive: true);
    });

    test('installPluginFromZip rejects zip with Zip Slip directory traversal files', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final tempDir = await Directory.systemTemp.createTemp('zeetools_test_sec_');
      final pluginsDir = Directory(p.join(tempDir.path, 'plugins'));
      await pluginsDir.create();

      final repo = PluginRepository(prefs, pluginsDirectory: pluginsDir);

      // Crear archivo ZIP con id válido pero archivo malicioso que intenta escapar
      final archive = Archive();
      final manifestJson = utf8.encode('{"id": "safe_plugin", "name": "Safe"}');
      archive.addFile(ArchiveFile('manifest.json', manifestJson.length, manifestJson));
      final evilBytes = utf8.encode('malicious content');
      archive.addFile(ArchiveFile('../../outside_escape.txt', evilBytes.length, evilBytes));
      final zipBytes = ZipEncoder().encode(archive);

      final zipFile = File(p.join(tempDir.path, 'test_zip_slip.zip'));
      await zipFile.writeAsBytes(zipBytes);

      await expectLater(
        () => repo.installPluginFromZip(zipFile.path),
        throwsA(isA<FormatException>()),
      );

      await tempDir.delete(recursive: true);
    });

    test('uninstallPlugin refuses to delete directories outside plugins folder', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final tempDir = await Directory.systemTemp.createTemp('zeetools_test_sec_');
      final pluginsDir = Directory(p.join(tempDir.path, 'plugins'));
      await pluginsDir.create();

      final repo = PluginRepository(prefs, pluginsDirectory: pluginsDir);

      final externalDir = Directory(p.join(tempDir.path, 'protected_folder'));
      await externalDir.create();
      final testFile = File(p.join(externalDir.path, 'important.txt'));
      await testFile.writeAsString('do not delete');

      // Intentar desinstalar apuntando a un directorio ajeno a pluginsDir
      await repo.uninstallPlugin('some_id', externalDir.path);

      // Verificar que el directorio y archivo protegidos no fueron borrados
      expect(await externalDir.exists(), isTrue);
      expect(await testFile.exists(), isTrue);

      await tempDir.delete(recursive: true);
    });
  });
}
