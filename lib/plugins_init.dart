import 'features/plugins/data/plugin_registry.dart';

/// Punto de extensión para registrar complementos y paquetes en ZeeTools.
///
/// Todas las extensiones que implementen `ZeeToolsPluginExtension`
/// se registran aquí para integrarse automáticamente en el Dashboard,
/// la pantalla de configuración y el sistema de navegación.
void registerCustomPlugins(PluginRegistry registry) {
  // Aquí se llamarán los registros de paquetes externos como zeepub_plugins.
}
