import 'package:flutter/material.dart';

// Complemento compilado con la aplicación: Flutter no carga código Dart en tiempo de ejecución, así que un
// complemento es un paquete o una carpeta del proyecto que se registra en lib/plugins.dart.
abstract class ZeeToolsPlugin {
  // Único entre los complementos: es el segmento de su ruta (/plugin/<id>) y su clave en las preferencias.
  String get id;

  String get name;

  String get description => '';

  IconData get icon => Icons.extension_rounded;

  // La página del complemento, con su propio Scaffold.
  Widget build(BuildContext context);
}
