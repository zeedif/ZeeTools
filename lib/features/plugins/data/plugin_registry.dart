import '../domain/zeetools_plugin.dart';

// Los complementos por id. Un id repetido o que no sirve como segmento de ruta detiene el arranque: ningún
// complemento puede ocupar el lugar de otro.
class PluginRegistry {
  PluginRegistry(Iterable<ZeeToolsPlugin> plugins) {
    for (final plugin in plugins) {
      if (!_validId.hasMatch(plugin.id)) throw ArgumentError.value(plugin.id, 'id', 'solo minúsculas, cifras, «_» y «-»');
      if (_byId.containsKey(plugin.id)) throw StateError('Dos complementos usan el id «${plugin.id}»');
      _byId[plugin.id] = plugin;
    }
  }

  static final _validId = RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$');
  final Map<String, ZeeToolsPlugin> _byId = {};

  Iterable<ZeeToolsPlugin> get all => _byId.values;

  ZeeToolsPlugin? operator [](String id) => _byId[id];
}
