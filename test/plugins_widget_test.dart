import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeetools/features/plugins/domain/plugin_manifest.dart';
import 'package:zeetools/features/plugins/presentation/cubit/plugins_cubit.dart';
import 'package:zeetools/features/plugins/presentation/cubit/plugins_state.dart';
import 'package:zeetools/features/plugins/presentation/views/plugin_details_dialog.dart';
import 'package:zeetools/features/plugins/presentation/views/plugin_error_boundary.dart';
import 'package:zeetools/features/plugins/presentation/views/plugins_settings_section.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

PluginManifest _manifest({String id = 'test', bool enabled = true}) =>
    PluginManifest(
      id: id,
      name: 'Complemento de Prueba',
      version: '1.0.0',
      author: 'Comunidad',
      description: 'Un plugin para tests.',
      directoryPath: '/tmp/plugins/$id',
      isEnabled: enabled,
    );

/// Fake cubit that emits a fixed state without touching any repository.
class _FakeCubit extends Cubit<PluginsState> implements PluginsCubit {
  _FakeCubit(super.initialState);

  @override
  Future<void> loadPlugins() async {}

  @override
  Future<void> togglePlugin(String id, bool enabled) async {
    final updated =
        state.plugins.map((p) => p.id == id ? p.copyWith(isEnabled: enabled) : p).toList();
    emit(state.copyWith(plugins: updated));
  }

  @override
  Future<void> installFromZip(String zipPath) async {}

  @override
  Future<void> uninstallPlugin(String id, String directoryPath) async {}

  @override
  Future<void> openFolder() async {}
}

Widget _wrap({required Widget child, required PluginsState state}) {
  return BlocProvider<PluginsCubit>(
    create: (_) => _FakeCubit(state),
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

// ---------------------------------------------------------------------------
// PluginErrorBoundary Tests
// ---------------------------------------------------------------------------

void main() {
  group('PluginErrorBoundary', () {
    testWidgets('renders child when no error has occurred', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PluginErrorBoundary(
            pluginName: 'TestPlugin',
            child: const Text('Contenido del plugin'),
          ),
        ),
      );

      expect(find.text('Contenido del plugin'), findsOneWidget);
      expect(find.text('Problema en el complemento "TestPlugin"'), findsNothing);
    });

    testWidgets('shows error screen and retry button after simulateError', (tester) async {
      final key = GlobalKey<PluginErrorBoundaryState>();

      await tester.pumpWidget(
        MaterialApp(
          home: PluginErrorBoundary(
            key: key,
            pluginName: 'TestPlugin',
            child: const Text('Contenido del plugin'),
          ),
        ),
      );

      key.currentState!.simulateError(Exception('fallo simulado'));
      await tester.pump();

      expect(find.text('Problema en el complemento "TestPlugin"'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('retry button clears the error and shows child again', (tester) async {
      final key = GlobalKey<PluginErrorBoundaryState>();

      await tester.pumpWidget(
        MaterialApp(
          home: PluginErrorBoundary(
            key: key,
            pluginName: 'TestPlugin',
            child: const Text('Contenido del plugin'),
          ),
        ),
      );

      key.currentState!.simulateError(Exception('fallo'));
      await tester.pump();
      expect(find.text('Reintentar'), findsOneWidget);

      await tester.tap(find.text('Reintentar'));
      await tester.pump();

      expect(find.text('Contenido del plugin'), findsOneWidget);
      expect(find.text('Problema en el complemento "TestPlugin"'), findsNothing);
    });

    testWidgets('captures real exceptions thrown during widget build and displays recovery screen', (tester) async {
      Object? reportedError;

      await tester.pumpWidget(
        MaterialApp(
          home: PluginErrorBoundary(
            pluginName: 'CrashingPlugin',
            onError: (err, _) => reportedError = err,
            child: Builder(
              builder: (context) {
                throw Exception('Fallo real en el método build del widget');
              },
            ),
          ),
        ),
      );

      // In Flutter widget tests, Flutter framework logs the exception
      expect(tester.takeException(), isNotNull);
      await tester.pump();

      expect(reportedError, isNotNull);
      expect(find.text('Problema en el complemento "CrashingPlugin"'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('retry remounts child and recovers if error condition ceases', (tester) async {
      bool fail = true;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setParentState) {
              return PluginErrorBoundary(
                pluginName: 'FlakyPlugin',
                child: Builder(
                  builder: (context) {
                    if (fail) throw Exception('Fallo transitorio');
                    return const Text('Plugin recuperado exitosamente');
                  },
                ),
              );
            },
          ),
        ),
      );

      expect(tester.takeException(), isNotNull);
      await tester.pump();
      expect(find.text('Problema en el complemento "FlakyPlugin"'), findsOneWidget);

      fail = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pump();

      expect(find.text('Plugin recuperado exitosamente'), findsOneWidget);
      expect(find.text('Problema en el complemento "FlakyPlugin"'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // PluginsSettingsSection — sin complementos
  // -------------------------------------------------------------------------

  group('PluginsSettingsSection — sin complementos', () {
    testWidgets('muestra mensaje de bienvenida y botones de acción', (tester) async {
      await tester.pumpWidget(
        _wrap(
          child: const PluginsSettingsSection(),
          state: const PluginsState(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Extiende ZeeTools instalando complementos (.zip).'), findsOneWidget);
      expect(find.text('No hay complementos instalados'), findsOneWidget);
      expect(find.text('Instalar (.zip)'), findsOneWidget);
      expect(find.text('Carpeta'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // PluginsSettingsSection — con complementos
  // -------------------------------------------------------------------------

  group('PluginsSettingsSection — con complementos', () {
    testWidgets('muestra lista con nombre, versión y switch', (tester) async {
      final plugin = _manifest(id: 'sample_plugin');

      await tester.pumpWidget(
        _wrap(
          child: const PluginsSettingsSection(),
          state: PluginsState(plugins: [plugin]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Complemento de Prueba'), findsOneWidget);
      expect(find.text('v1.0.0'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('muestra contador correcto en el encabezado', (tester) async {
      final plugins = [_manifest(id: 'p1'), _manifest(id: 'p2', enabled: false)];

      await tester.pumpWidget(
        _wrap(
          child: const PluginsSettingsSection(),
          state: PluginsState(plugins: plugins),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('2 complementos instalados (1 activo)'),
        findsOneWidget,
      );
    });

    testWidgets('abre el diálogo de detalles al pulsar sobre el plugin', (tester) async {
      final plugin = _manifest(id: 'sample_plugin');

      await tester.pumpWidget(
        _wrap(
          child: const PluginsSettingsSection(),
          state: PluginsState(plugins: [plugin]),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Complemento de Prueba'));
      await tester.pumpAndSettle();

      expect(find.byType(PluginDetailsDialog), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // PluginsSettingsSection — estado de carga
  // -------------------------------------------------------------------------

  group('PluginsSettingsSection — cargando', () {
    testWidgets('muestra indicador de progreso mientras carga', (tester) async {
      await tester.pumpWidget(
        _wrap(
          child: const PluginsSettingsSection(),
          state: const PluginsState(isLoading: true),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // PluginDetailsDialog
  // -------------------------------------------------------------------------

  group('PluginDetailsDialog', () {
    testWidgets('muestra nombre, versión y autor del complemento', (tester) async {
      final plugin = _manifest(id: 'sample_plugin');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showDialog(
                  context: ctx,
                  builder: (_) => PluginDetailsDialog(plugin: plugin),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Complemento de Prueba'), findsAtLeastNWidgets(1));
      expect(find.textContaining('1.0.0'), findsAtLeastNWidgets(1));
      expect(find.textContaining('Comunidad'), findsAtLeastNWidgets(1));
    });
  });
}
