import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'inject_dependencies.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await injectDependencies();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    final prefs = getIt<SharedPreferences>();
    final width = prefs.getDouble('window_width') ?? 1024.0;
    final height = prefs.getDouble('window_height') ?? 768.0;
    final dx = prefs.getDouble('window_x');
    final dy = prefs.getDouble('window_y');

    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: Size(width, height),
        minimumSize: const Size(360, 360),
        center: dx == null || dy == null,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.normal,
        title: 'ZeeTools',
      ),
      () async {
        if (dx != null && dy != null) {
          await windowManager.setPosition(Offset(dx, dy));
        }
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  runApp(const MyApp());
}
