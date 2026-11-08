import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zeetools/features/home/home_route.dart';
import 'package:zeetools/features/plugins/data/plugin_registry.dart';
import 'package:zeetools/features/plugins/domain/zeetools_plugin.dart';
import 'package:zeetools/features/settings/data/preferences_repo.dart';
import 'package:zeetools/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:zeetools/features/settings/presentation/views/settings_view.dart';
import 'package:zeetools/inject_dependencies.dart';

class _Plugin(@override final String id, @override final String name) extends ZeeToolsPlugin {
  @override
  Widget build(BuildContext context) => Scaffold(body: Text('Página de $name'));
}

void main() {
  late SettingsCubit settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    getIt.registerSingleton(PluginRegistry([_Plugin('calendario', 'Calendario'), _Plugin('grupos', 'Grupos')]));
    settings = SettingsCubit(PreferencesRepositoryImpl(await SharedPreferences.getInstance()));
  });

  Future<GoRouter> pumpApp(WidgetTester tester) async {
    final router = GoRouter(routes: [HomeRoute.route]);
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(BlocProvider.value(value: settings, child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    return router;
  }

  test('ningún complemento ocupa el lugar de otro: id repetido o inválido detiene el registro', () {
    expect(() => PluginRegistry([_Plugin('uno', 'A'), _Plugin('uno', 'B')]), throwsStateError);
    expect(() => PluginRegistry([_Plugin('../uno', 'A')]), throwsArgumentError);
    expect(() => PluginRegistry([_Plugin('Uno', 'A')]), throwsArgumentError);
  });

  test('los complementos desactivados se guardan en una sola preferencia', () async {
    await settings.setPluginEnabled('grupos', false);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('disabled_plugins'), ['grupos']);
    expect(PreferencesRepositoryImpl(prefs).getPreferences().disabledPlugins, {'grupos'});
    await settings.setPluginEnabled('grupos', true);
    expect(prefs.getStringList('disabled_plugins'), isEmpty);
  });

  testWidgets('el dashboard muestra los complementos activos y abre su página', (tester) async {
    await settings.setPluginEnabled('grupos', false);
    await pumpApp(tester);
    expect(find.text('Calendario'), findsOneWidget);
    expect(find.text('Grupos'), findsNothing);
    await tester.tap(find.text('Calendario'));
    await tester.pumpAndSettle();
    expect(find.text('Página de Calendario'), findsOneWidget);
  });

  testWidgets('un complemento desactivado o inexistente vuelve al dashboard', (tester) async {
    await settings.setPluginEnabled('grupos', false);
    final router = await pumpApp(tester);
    for (final location in ['/plugin/grupos', '/plugin/nada']) {
      router.go(location);
      await tester.pumpAndSettle();
      expect(find.text('Dashboard'), findsOneWidget);
    }
  });

  testWidgets('la configuración activa y desactiva cada complemento', (tester) async {
    await tester.pumpWidget(BlocProvider.value(value: settings, child: const MaterialApp(home: SettingsView())));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Grupos'));
    await tester.pumpAndSettle();
    expect(settings.state.preferences.disabledPlugins, {'grupos'});
  });
}
