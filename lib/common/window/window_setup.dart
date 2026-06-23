import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

class WindowSetup with WindowListener {
  final SharedPreferences _prefs;

  WindowSetup({required this._prefs});

  Future<void> init() async {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;

    await windowManager.ensureInitialized();
    windowManager.addListener(this);

    final width = _prefs.getDouble('window_width') ?? 1024.0;
    final height = _prefs.getDouble('window_height') ?? 768.0;
    final dx = _prefs.getDouble('window_x');
    final dy = _prefs.getDouble('window_y');

    final windowOptions = WindowOptions(
      size: Size(width, height),
      minimumSize: const Size(360, 360),
      center: dx == null || dy == null,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: 'ZeeTools',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (dx != null && dy != null) {
        await windowManager.setPosition(Offset(dx, dy));
      }
      await windowManager.show();
      await windowManager.focus();
    });
  }

  @override
  void onWindowResized() async {
    final size = await windowManager.getSize();
    await _prefs.setDouble('window_width', size.width);
    await _prefs.setDouble('window_height', size.height);
  }

  @override
  void onWindowMoved() async {
    final position = await windowManager.getPosition();
    await _prefs.setDouble('window_x', position.dx);
    await _prefs.setDouble('window_y', position.dy);
  }
}
