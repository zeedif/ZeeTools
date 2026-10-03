import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'native_tool.dart';

class NativeToolException implements Exception {
  const NativeToolException(this.message);

  final String message;

  @override
  String toString() => message;
}

class NativeToolset {
  const NativeToolset(this._paths);

  final Map<NativeTool, String> _paths;

  bool has(NativeTool tool) => _paths.containsKey(tool);

  List<NativeTool> get missing => NativeTool.values.where((t) => !has(t)).toList();

  // Devuelve stdout; lanza NativeToolException si la herramienta falta o termina con error.
  Future<String> run(NativeTool tool, List<String> args) async {
    final path = _paths[tool];
    if (path == null) throw NativeToolException('${tool.command} no está disponible');
    final result = await Process.run(path, args);
    if (result.exitCode != 0) {
      final detail = '${result.stderr}'.trim().isNotEmpty ? '${result.stderr}'.trim() : '${result.stdout}'.trim();
      throw NativeToolException('${tool.command} falló (${result.exitCode}): ${detail.length > 300 ? detail.substring(0, 300) : detail}');
    }
    return '${result.stdout}';
  }
}

abstract interface class NativeToolsRepository {
  Future<NativeToolset> ensureTools({void Function(String message)? onProgress});
}

class NativeToolsRepositoryImpl(final String _toolsDir) implements NativeToolsRepository {
  NativeToolset? _cached;

  @override
  Future<NativeToolset> ensureTools({void Function(String message)? onProgress}) async {
    return _cached ??= Platform.isWindows ? await _installWindows(onProgress) : await _lookupInPath();
  }

  Future<NativeToolset> _installWindows(void Function(String message)? onProgress) async {
    final dir = Directory(p.join(_toolsDir, 'windows-x64'));
    await dir.create(recursive: true);
    File fileFor(NativeTool tool) => File(p.join(dir.path, tool.windowsFileName));

    for (final package in {
      for (final tool in NativeTool.values)
        if (!fileFor(tool).existsSync()) tool.windowsPackage,
    }) {
      onProgress?.call('Descargando ${package.name}…');
      final bytes = await _download(package.windowsUrl);
      final members = {
        for (final tool in NativeTool.values)
          if (tool.windowsPackage == package) tool.windowsMember: fileFor(tool).path,
      };
      onProgress?.call('Extrayendo ${package.name}…');
      await Isolate.run(() => _extractMembers(bytes, members));
    }

    return NativeToolset({
      for (final tool in NativeTool.values)
        if (fileFor(tool).existsSync()) tool: fileFor(tool).path,
    });
  }

  Future<NativeToolset> _lookupInPath() async {
    final paths = <NativeTool, String>{};
    for (final tool in NativeTool.values) {
      final result = await Process.run('which', [tool.command]);
      final path = '${result.stdout}'.trim();
      if (result.exitCode == 0 && path.isNotEmpty) paths[tool] = path;
    }
    return NativeToolset(paths);
  }

  static Future<Uint8List> _download(String url) async {
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(Uri.parse(url))).close();
      if (response.statusCode != HttpStatus.ok) {
        throw NativeToolException('No se pudo descargar $url (HTTP ${response.statusCode})');
      }
      final builder = BytesBuilder(copy: false);
      await response.forEach(builder.add);
      return builder.takeBytes();
    } on SocketException catch (e) {
      throw NativeToolException('No se pudo descargar $url: ${e.message}');
    } finally {
      client.close();
    }
  }

  // members: sufijo de ruta dentro del zip → ruta de destino.
  static void _extractMembers(Uint8List zipBytes, Map<String, String> members) {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    for (final MapEntry(key: member, value: target) in members.entries) {
      final entry = archive.files.where((f) => f.isFile && (f.name == member || f.name.endsWith('/$member'))).firstOrNull;
      if (entry == null) throw NativeToolException('$member no está en el paquete descargado');
      File(target).writeAsBytesSync(entry.content);
    }
  }
}
